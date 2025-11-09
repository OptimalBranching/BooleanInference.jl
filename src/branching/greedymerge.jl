# Generate a key for a clause based on its fields
@inline clause_key(cl::Clause{INT}) where {INT} = (getfield(cl, 1), getfield(cl, 2))

# Get size reduction from cache or compute and cache it
function cached_size_reduction!(
    cache::Dict{Tuple{INT,INT},Float64},
    problem::OptimalBranchingCore.AbstractProblem,
    m::OptimalBranchingCore.AbstractMeasure,
    variables::Vector{Int},
    clause::Clause{INT}
) where {INT}
    key = clause_key(clause)
    return get!(cache, key) do
        Float64(OptimalBranchingCore.size_reduction(problem, m, clause, variables))
    end
end

# Select the best representative clause from each row based on size reduction
function select_representatives!(cls::Vector{Vector{Clause{INT}}}, cache::Dict{Tuple{INT,INT},Float64},problem::OptimalBranchingCore.AbstractProblem, variables::Vector{Int}, m::OptimalBranchingCore.AbstractMeasure) where {INT}
    size_reductions = Vector{Float64}(undef, length(cls))
    @inbounds for (idx, row) in pairs(cls)
        best_val = -Inf
        best_pos = 0
        @inbounds for k in eachindex(row)
            reduction = cached_size_reduction!(cache, problem, m, variables, row[k])
            if reduction > best_val && reduction > 0 && isfinite(reduction)
                best_val = reduction
                best_pos = k
            end
        end
        size_reductions[idx] = best_val
        if best_pos > 1
            row[1], row[best_pos] = row[best_pos], row[1]
        end
    end
    return size_reductions
end

# Remove rows with invalid (non-finite or non-positive) size reductions
function drop_invalid_rows!(cls::Vector{Vector{Clause{INT}}}, size_reductions::Vector{Float64}) where {INT}
    keep = isfinite.(size_reductions) .& (size_reductions .> 0)
    all(keep) && return cls, size_reductions
    return cls[keep], size_reductions[keep]
end

# Remove duplicate singleton clauses from the clause set
function deduplicate_singletons!(cls::Vector{Vector{Clause{INT}}}, size_reductions::Vector{Float64}) where {INT}
    seen = Dict{Tuple{INT,INT},Int}()
    mask = trues(length(cls))
    @inbounds for i in 1:length(cls)
        if length(cls[i]) == 1
            key = clause_key(cls[i][1])
            if haskey(seen, key)
                mask[i] = false
            else
                seen[key] = i
            end
        end
    end
    if all(mask)
        return cls, size_reductions
    end
    return cls[mask], size_reductions[mask]
end

# Find the best clause to merge from two clause vectors
function best_merge_clause(
    cache::Dict{Tuple{INT,INT},Float64},
    problem::OptimalBranchingCore.AbstractProblem,
    m::OptimalBranchingCore.AbstractMeasure,
    variables::Vector{Int},
    left::Vector{Clause{INT}},
    right::Vector{Clause{INT}}
) where {INT}
    best_clause = nothing
    best_reduction = -Inf
    nvars = length(variables)
    @inbounds for cl_left in left
        @inbounds for cl_right in right
            merged = OptimalBranchingCore.gather2(nvars, cl_left, cl_right)
            iszero(merged.mask) && continue
            reduction = cached_size_reduction!(cache, problem, m, variables, merged)
            if reduction > best_reduction && reduction > 0 && isfinite(reduction)
                best_clause = merged
                best_reduction = reduction
            end
        end
    end
    return best_clause, best_reduction
end

# Enqueue a merge pair if it's beneficial (finite positive reduction with negative energy change)
@inline function maybe_enqueue!(queue::PriorityQueue{NTuple{2,Int},Float64}, idx_a::Int, idx_b::Int, reduction::Float64, weights::Vector{Float64}, γ::Float64)
    if !isfinite(reduction) || reduction <= 0
        return
    end
    dE = γ^(-reduction) - weights[idx_a] - weights[idx_b]
    dE <= -1e-12 && enqueue!(queue, (idx_a, idx_b), dE)
end

# Enqueue all beneficial merge pairs from the clause set
function enqueue_beneficial_merges!(
    queue::PriorityQueue{NTuple{2,Int},Float64},
    cls::Vector{Vector{Clause{INT}}},
    γ::Float64,
    weights::Vector{Float64},
    cache::Dict{Tuple{INT,INT},Float64},
    problem::OptimalBranchingCore.AbstractProblem,
    variables::Vector{Int},
    m::OptimalBranchingCore.AbstractMeasure
) where {INT}
    nc = length(cls)
    @inbounds for i in 1:nc-1
        row_i = cls[i]
        for j in i+1:nc
            clause, reduction = best_merge_clause(cache, problem, m, variables, row_i, cls[j])
            clause === nothing && continue
            maybe_enqueue!(queue, i, j, reduction, weights, γ)
        end
    end
end

# Remove queue entries related to a specific row
function purge_queue_entries!(queue::PriorityQueue{NTuple{2,Int},Float64}, mask::BitVector, rowid::Int, nc::Int)
    mask[rowid] = false
    @inbounds for l in 1:nc
        if mask[l]
            a, b = minmax(rowid, l)
            haskey(queue, (a, b)) && delete!(queue, (a, b))
        end
    end
end

# Process the merge queue and perform beneficial merges
function process_merge_queue!(
    queue::PriorityQueue{NTuple{2,Int},Float64},
    cls::Vector{Vector{Clause{INT}}}, size_reductions::Vector{Float64},
    weights::Vector{Float64}, mask::BitVector, γ::Float64,
    cache::Dict{Tuple{INT,INT},Float64},
    problem::OptimalBranchingCore.AbstractProblem,
    variables::Vector{Int},
    m::OptimalBranchingCore.AbstractMeasure
) where {INT}
    nc = length(cls)
    any_merge = false
    while !isempty(queue)
        (i, j) = dequeue!(queue)
        if !mask[i] || !mask[j]
            continue
        end
        clause, new_reduction = best_merge_clause(cache, problem, m, variables, cls[i], cls[j])
        clause === nothing && continue

        purge_queue_entries!(queue, mask, i, nc)
        purge_queue_entries!(queue, mask, j, nc)

        mask[i] = true
        cls[i] = [clause]
        size_reductions[i] = new_reduction
        weights[i] = γ^(-new_reduction)
        any_merge = true

        @inbounds for l in 1:nc
            if i !== l && mask[l]
                a, b = minmax(i, l)
                _, reduction = best_merge_clause(cache, problem, m, variables, cls[a], cls[b])
                maybe_enqueue!(queue, a, b, reduction, weights, γ)
            end
        end
    end
    return any_merge
end

# Greedy merge algorithm to find optimal branching clauses
function OptimalBranchingCore.greedymerge(cls::Vector{Vector{Clause{INT}}}, problem::TNProblem, variables::Vector{T}, m::OptimalBranchingCore.AbstractMeasure) where {INT<:Integer, T}
    cache = Dict{Tuple{INT,INT},Float64}()
    working = copy(cls)
    size_reductions = select_representatives!(working, cache, problem, variables, m)
    working, size_reductions = drop_invalid_rows!(working, size_reductions)
    if isempty(working)
        @debug "greedymerge: no valid clauses remain after filtering; returning empty result"
        return OptimalBranchingResult(DNF(Clause{INT}[]), Float64[], Inf)
    end

    while true
        working, size_reductions = deduplicate_singletons!(working, size_reductions)
        nc = length(working)
        mask = trues(nc)
        γ = OptimalBranchingCore.complexity_bv(size_reductions)
        weights = map(s -> γ^(-s), size_reductions)
        queue = PriorityQueue{NTuple{2, Int}, Float64}()

        enqueue_beneficial_merges!(queue, working, γ, weights, cache, problem, variables, m)
        if isempty(queue)
            return OptimalBranchingResult(DNF(first.(working)), size_reductions, γ)
        end

        any_merge = process_merge_queue!(queue, working, size_reductions, weights, mask, γ, cache, problem, variables, m)
        if !any_merge
            return OptimalBranchingResult(DNF(first.(working)), size_reductions, γ)
        end

        working = working[mask]
        size_reductions = size_reductions[mask]
    end
end
