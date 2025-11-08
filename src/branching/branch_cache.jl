# Branch application caching infrastructure

# Look up cached result of applying a branch
@inline function lookup_branch_cache(problem::TNProblem, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}) where {INT}
    ws = problem.ws
    doms_id = Base.objectid(problem.doms)
    inner = get(ws.branch_cache, doms_id, nothing)
    inner === nothing && return nothing
    key = (Base.objectid(variables), clause_key(clause))
    return get(inner, key, nothing)
end

# Store result of applying a branch in cache
# assignments: Vector of (var_id, value::Bool) tuples for variables fixed by the clause
@inline function store_branch_cache!(problem::TNProblem, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}, doms::Vector{DomainMask}, n_unfixed::Int, local_value::Int, assignments::Vector{Tuple{Int,Bool}}) where {INT}
    ws = problem.ws
    doms_id = Base.objectid(problem.doms)
    inner = get!(ws.branch_cache, doms_id) do
        Dict{Tuple{UInt, Any}, Any}()
    end
    key = (Base.objectid(variables), clause_key(clause))
    inner[key] = (doms=doms, n_unfixed=n_unfixed, local_value=local_value, assignments=assignments)
    return nothing
end
