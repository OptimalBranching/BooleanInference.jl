"""
    TensorRegion

A region in the tensor network formed by clustering tensors.
Unlike variable-based Region, TensorRegion is defined purely by tensor membership.
"""
mutable struct TensorRegion
    id::Int                    # Region ID
    tensors::Set{Int}          # Tensor IDs in this region  
    open_legs::Set{Int}        # Variables shared with other regions (boundary)
    internal_legs::Set{Int}    # Variables fully contained in this region
end

function Base.show(io::IO, r::TensorRegion)
    print(io, "TensorRegion(id=$(r.id), tensors=$(length(r.tensors)), open=$(length(r.open_legs)), internal=$(length(r.internal_legs)))")
end

"""
    RegionGraph

Maintains the set of TensorRegions and their adjacency (shared legs between regions).
"""
mutable struct RegionGraph
    regions::Dict{Int,TensorRegion}           # region_id -> TensorRegion
    tensor_to_region::Vector{Int}              # tensor_id -> region_id
    adjacency::Dict{Tuple{Int,Int},Set{Int}}  # (region_a, region_b) -> shared variables
    next_region_id::Int
end

function Base.show(io::IO, rg::RegionGraph)
    print(io, "RegionGraph($(length(rg.regions)) regions)")
end

"""
    compute_open_legs(cn::ConstraintNetwork, tensors::Set{Int})

Compute the "open legs" (external boundary variables) for a set of tensors.
A variable is an open leg if it appears in tensors both inside and outside the set.
"""
function compute_open_legs(cn::ConstraintNetwork, tensors::Set{Int})
    # Count how many tensors in `tensors` each variable appears in
    var_count_inside = Dict{Int,Int}()

    for tid in tensors
        for var in cn.tensors[tid].var_axes
            var_count_inside[var] = get(var_count_inside, var, 0) + 1
        end
    end

    # A variable is "open" if it appears in the region AND in some tensor outside
    open_legs = Set{Int}()
    internal_legs = Set{Int}()

    for (var, count_inside) in var_count_inside
        total_count = length(cn.v2t[var])
        if count_inside < total_count
            # Variable connects to tensors outside this region
            push!(open_legs, var)
        else
            # Variable is fully contained in this region
            push!(internal_legs, var)
        end
    end

    return open_legs, internal_legs
end

"""
    compute_all_vars(cn::ConstraintNetwork, tensors::Set{Int})

Get all variables touched by a set of tensors.
"""
function compute_all_vars(cn::ConstraintNetwork, tensors::Set{Int})
    vars = Set{Int}()
    for tid in tensors
        for var in cn.tensors[tid].var_axes
            push!(vars, var)
        end
    end
    return vars
end

"""
    compute_merge_gain(cn::ConstraintNetwork, tensors_a::Set{Int}, tensors_b::Set{Int})

Compute the "gain" from merging two regions:
    Gain = OpenLegs(A) + OpenLegs(B) - OpenLegs(A ∪ B)

This represents how many "shared variables" are internalized by the merge.
Higher gain means the merge "eats" more legs, making the network tighter.
"""
function compute_merge_gain(cn::ConstraintNetwork, tensors_a::Set{Int}, tensors_b::Set{Int})
    open_a, _ = compute_open_legs(cn, tensors_a)
    open_b, _ = compute_open_legs(cn, tensors_b)

    merged = union(tensors_a, tensors_b)
    open_merged, _ = compute_open_legs(cn, merged)

    return length(open_a) + length(open_b) - length(open_merged)
end

"""
    init_region_graph(cn::ConstraintNetwork, doms::Vector{DomainMask})

Initialize a RegionGraph where each tensor starts as its own region.
Only considers tensors that have at least one unfixed variable.
"""
function init_region_graph(cn::ConstraintNetwork, doms::Vector{DomainMask})
    regions = Dict{Int,TensorRegion}()
    tensor_to_region = zeros(Int, length(cn.tensors))
    adjacency = Dict{Tuple{Int,Int},Set{Int}}()

    region_id = 0
    for (tid, tensor) in enumerate(cn.tensors)
        # Check if tensor has any unfixed variables
        has_unfixed = any(v -> !is_fixed(doms[v]), tensor.var_axes)
        if !has_unfixed
            continue  # Skip fully-fixed tensors
        end

        region_id += 1
        tensors_set = Set([tid])
        open_legs, internal_legs = compute_open_legs(cn, tensors_set)

        # Filter to only unfixed variables
        open_legs = Set(filter(v -> !is_fixed(doms[v]), open_legs))
        internal_legs = Set(filter(v -> !is_fixed(doms[v]), internal_legs))

        regions[region_id] = TensorRegion(region_id, tensors_set, open_legs, internal_legs)
        tensor_to_region[tid] = region_id
    end

    # Build adjacency: two regions are adjacent if they share a variable
    for var_id in 1:length(cn.vars)
        is_fixed(doms[var_id]) && continue

        # Find all regions that touch this variable
        region_set = Set{Int}()
        for tid in cn.v2t[var_id]
            rid = tensor_to_region[tid]
            rid > 0 && push!(region_set, rid)
        end

        # Add edges between all pairs of regions that share this variable
        region_list = collect(region_set)
        for i in 1:length(region_list)
            for j in (i+1):length(region_list)
                r1, r2 = minmax(region_list[i], region_list[j])
                key = (r1, r2)
                if !haskey(adjacency, key)
                    adjacency[key] = Set{Int}()
                end
                push!(adjacency[key], var_id)
            end
        end
    end

    return RegionGraph(regions, tensor_to_region, adjacency, region_id)
end

"""
    merge_regions!(rg::RegionGraph, cn::ConstraintNetwork, doms::Vector{DomainMask}, r1_id::Int, r2_id::Int)

Merge region r2 into r1, updating the graph structure.
"""
function merge_regions!(rg::RegionGraph, cn::ConstraintNetwork, doms::Vector{DomainMask}, r1_id::Int, r2_id::Int)
    r1 = rg.regions[r1_id]
    r2 = rg.regions[r2_id]

    # Merge tensors
    union!(r1.tensors, r2.tensors)

    # Update tensor_to_region
    for tid in r2.tensors
        rg.tensor_to_region[tid] = r1_id
    end

    # Recompute open/internal legs for merged region
    open_legs, internal_legs = compute_open_legs(cn, r1.tensors)
    r1.open_legs = Set(filter(v -> !is_fixed(doms[v]), open_legs))
    r1.internal_legs = Set(filter(v -> !is_fixed(doms[v]), internal_legs))

    # Update adjacency: collect all neighbors of r2
    r2_neighbors = Set{Int}()
    keys_to_remove = Tuple{Int,Int}[]

    for (key, shared_vars) in rg.adjacency
        a, b = key
        if a == r2_id
            push!(r2_neighbors, b)
            push!(keys_to_remove, key)
        elseif b == r2_id
            push!(r2_neighbors, a)
            push!(keys_to_remove, key)
        end
    end

    # Remove old adjacency entries involving r2
    for key in keys_to_remove
        delete!(rg.adjacency, key)
    end

    # Also remove r1-r2 adjacency (if exists)
    delete!(rg.adjacency, minmax(r1_id, r2_id))

    # Add/update adjacency between r1 and r2's former neighbors
    for neighbor_id in r2_neighbors
        neighbor_id == r1_id && continue
        haskey(rg.regions, neighbor_id) || continue

        neighbor = rg.regions[neighbor_id]

        # Compute shared variables between r1 (merged) and neighbor
        shared = intersect(r1.open_legs, neighbor.open_legs)

        if !isempty(shared)
            key = minmax(r1_id, neighbor_id)
            rg.adjacency[key] = shared
        end
    end

    # Recompute adjacency for r1 with all its neighbors
    keys_to_update = Tuple{Int,Int}[]
    for (key, _) in rg.adjacency
        a, b = key
        if a == r1_id || b == r1_id
            push!(keys_to_update, key)
        end
    end

    for key in keys_to_update
        a, b = key
        other_id = (a == r1_id) ? b : a
        haskey(rg.regions, other_id) || continue

        other = rg.regions[other_id]
        shared = intersect(r1.open_legs, other.open_legs)

        if isempty(shared)
            delete!(rg.adjacency, key)
        else
            rg.adjacency[key] = shared
        end
    end

    # Remove r2 from regions
    delete!(rg.regions, r2_id)
end

"""
    greedy_cluster!(cn::ConstraintNetwork, doms::Vector{DomainMask}; 
                    max_vars::Int=10, min_gain::Int=2)

Greedily merge tensor regions based on the Gain metric until no beneficial merge exists.

Arguments:
- `max_vars`: Maximum number of unfixed variables allowed in a merged region (branch table size = 2^max_vars)
- `min_gain`: Minimum gain required to perform a merge (higher = tighter clusters)

Returns a RegionGraph with the final clustering.
"""
function greedy_cluster!(cn::ConstraintNetwork, doms::Vector{DomainMask};
    max_vars::Int=10, min_gain::Int=2)
    rg = init_region_graph(cn, doms)

    # Priority queue: store (gain, r1_id, r2_id) tuples
    # We'll use a simple approach: recompute best merge each iteration

    while true
        best_gain = min_gain - 1  # Must exceed min_gain
        best_pair = nothing

        for ((r1_id, r2_id), shared_vars) in rg.adjacency
            haskey(rg.regions, r1_id) || continue
            haskey(rg.regions, r2_id) || continue

            r1 = rg.regions[r1_id]
            r2 = rg.regions[r2_id]

            # Check merged size constraint
            merged_vars = union(r1.open_legs, r1.internal_legs, r2.open_legs, r2.internal_legs)
            if length(merged_vars) > max_vars
                continue
            end

            # Compute gain
            gain = compute_merge_gain(cn, r1.tensors, r2.tensors)

            if gain > best_gain
                best_gain = gain
                best_pair = (r1_id, r2_id)
            end
        end

        if isnothing(best_pair)
            break  # No beneficial merge found
        end

        # Perform the merge
        r1_id, r2_id = best_pair
        merge_regions!(rg, cn, doms, r1_id, r2_id)
    end

    return rg
end

"""
    get_sorted_regions(rg::RegionGraph)

Return regions sorted by number of open legs (ascending).
Regions with fewer open legs are often better branching candidates.
"""
function get_sorted_regions(rg::RegionGraph)
    regions = collect(values(rg.regions))
    sort!(regions, by=r -> length(r.open_legs))
    return regions
end

"""
    region_to_legacy(rg::RegionGraph, cn::ConstraintNetwork, region::TensorRegion)

Convert a TensorRegion to the legacy Region format for compatibility with existing code.
"""
function region_to_legacy(cn::ConstraintNetwork, region::TensorRegion)
    tensors = sort!(collect(region.tensors))
    vars = sort!(collect(union(region.open_legs, region.internal_legs)))
    # Use first tensor as "focus" ID for legacy compatibility
    focus_id = isempty(tensors) ? 0 : first(tensors)
    return Region(focus_id, tensors, vars)
end
