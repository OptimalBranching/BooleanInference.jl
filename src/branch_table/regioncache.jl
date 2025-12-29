struct Region
    id::Int
    tensors::Vector{Int}
    vars::Vector{Int}
end

function Base.show(io::IO, region::Region)
    print(io, "Region(focus=$(region.id), tensors=$(region.tensors), vars=$(region.vars))")
end

function Base.copy(region::Region)
    return Region(region.id, region.tensors, region.vars)
end

"""
    RegionCache

Cache for region contraction results, keyed by the tensor ID set.
This allows sharing contraction results across different variables that
happen to produce the same region (same set of tensors).
"""
struct RegionCache{S}
    selector::S
    initial_doms::Vector{DomainMask}

    # Primary cache: keyed by sorted tensor IDs (as a tuple for hashing)
    tensor_set_to_configs::Dict{Vector{Int},Vector{UInt64}}

    # Secondary lookup: var_id -> Region (for quick region retrieval)
    var_to_region::Dict{Int,Region}
end

function init_cache(problem::TNProblem, table_solver::AbstractTableSolver, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::AbstractSelector)
    return RegionCache(
        selector,
        copy(problem.doms),
        Dict{Vector{Int},Vector{UInt64}}(),
        Dict{Int,Region}()
    )
end

"""
Get or compute region data for a variable.
The contraction result is cached by tensor set, enabling cross-variable reuse.
"""
function get_region_data!(cache::RegionCache, problem::TNProblem, var_id::Int)
    # Step 1: Get or create region for this variable
    if !haskey(cache.var_to_region, var_id)
        region = create_region(problem.static, cache.initial_doms, var_id, cache.selector)
        cache.var_to_region[var_id] = region
    end
    region = cache.var_to_region[var_id]

    # Step 2: Check if we've already contracted this tensor set
    tensor_key = sort(region.tensors)  # Canonical key

    if !haskey(cache.tensor_set_to_configs, tensor_key)
        # Compute and cache
        contracted_tensor, _ = contract_region(problem.static, region, cache.initial_doms)
        configs = map(packint, findall(isone, contracted_tensor))
        cache.tensor_set_to_configs[tensor_key] = configs
    end

    return region, cache.tensor_set_to_configs[tensor_key]
end
