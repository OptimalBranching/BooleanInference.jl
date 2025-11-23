function apply_branch!(problem::TNProblem, clause::OptimalBranchingCore.Clause, variables::Vector{Int})
    doms, changed_vars = apply_clause(clause, variables, problem.doms)
    isempty(changed_vars) && return problem.doms

    touched_tensors = unique(vcat([problem.static.v2t[v] for v in changed_vars]...))
    propagated_doms, _ = propagate(problem.static, doms, touched_tensors)

    @assert !has_contradiction(propagated_doms) "Contradiction found when applying clause $clause"
    problem.propagated_cache[clause] = propagated_doms
    return propagated_doms
end

function OptimalBranchingCore.size_reduction(p::TNProblem{INT}, m::AbstractMeasure, cl::Clause{INT}, variables::Vector{Int}) where {INT}
    newdoms = haskey(p.propagated_cache, cl) ? p.propagated_cache[cl] : apply_branch!(p, cl, variables)
    return measure(p, m) - measure(TNProblem(p.static, newdoms, INT), m)
end

# Main branch-and-reduce algorithm
function bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer)
    cache = init_cache(problem, config.table_solver, config.measure, config.set_cover_solver, config.selector)
    return _bbsat!(problem, config, reducer, cache)
end

function _bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer, region_cache::RegionCache)
    stats = problem.stats
    # println("================================================")
    is_solved(problem) && return Result(true, problem.doms, copy(stats))

    subproblems = findbest(region_cache, problem, config.measure, config.set_cover_solver)
    isempty(subproblems) && return Result(false, DomainMask[], copy(stats))
    record_branch!(stats, length(subproblems))
    @inbounds for subproblem_doms in subproblems
        subproblem = TNProblem(problem.static, subproblem_doms, problem.stats, Dict{Clause{UInt64}, Vector{DomainMask}}())
        # No need to update cache - it's shared and immutable
        result = _bbsat!(subproblem, config, reducer, region_cache)
        result.found && return result
    end
    return Result(false, DomainMask[], copy(stats))
end