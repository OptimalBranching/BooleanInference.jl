# Branch application caching infrastructure

# Look up cached result of applying a branch
@inline function lookup_branch_cache(problem::TNProblem, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int})::Union{Nothing, BranchCacheEntry} where {INT}
    ws = problem.ws
    doms_id = Base.objectid(problem.doms)
    inner_dict = get(ws.branch_cache, doms_id, nothing)
    inner_dict === nothing && return nothing

    # Type-assert the inner dict to help inference
    inner = inner_dict::Dict{Any, BranchCacheEntry}
    key = (Base.objectid(variables), clause_key(clause))
    result = get(inner, key, nothing)
    return result::Union{Nothing, BranchCacheEntry}
end

# Store result of applying a branch in cache
# assignments: Vector of (var_id, value::Bool) tuples for variables fixed by the clause
@inline function store_branch_cache!(problem::TNProblem, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}, doms::Vector{DomainMask}, n_unfixed::Int, local_value::Int, assignments::Vector{Tuple{Int,Bool}}) where {INT}
    ws = problem.ws
    doms_id = Base.objectid(problem.doms)
    inner_dict = get!(ws.branch_cache, doms_id) do
        Dict{Any, BranchCacheEntry}()
    end
    # Type-assert to help inference
    inner = inner_dict::Dict{Any, BranchCacheEntry}
    key = (Base.objectid(variables), clause_key(clause))
    entry = BranchCacheEntry(doms, n_unfixed, local_value, assignments)
    inner[key] = entry
    return nothing
end
