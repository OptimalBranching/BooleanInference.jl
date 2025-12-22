@inline probe_branch!(problem::TNProblem, buffer::SolverBuffer, base_doms::Vector{DomainMask}, clause::Clause, variables::Vector{Int}) = probe_assignment_core!(problem, buffer, base_doms, variables, clause.mask, clause.val)

function OptimalBranchingCore.size_reduction(p::TNProblem, m::AbstractMeasure, cl::Clause{UInt64}, variables::Vector{Int})
    if haskey(p.buffer.branching_cache, cl)
        new_measure = p.buffer.branching_cache[cl]
    else
        new_doms = probe_branch!(p, p.buffer, p.doms, cl, variables)
        @assert !has_contradiction(new_doms) "Contradiction found when probing branch $cl"
        new_measure = measure_core(p.static, new_doms, m)
        p.buffer.branching_cache[cl] = new_measure
    end
    r = measure(p, m) - new_measure
    return r
end

# the static parameters are not changed during the search
struct SearchContext
    static::ConstraintNetwork
    stats::BranchingStats
    buffer::SolverBuffer
    learned_clauses::Vector{ClauseTensor}
    v2c::Vector{Vector{Int}}
    config::OptimalBranchingCore.BranchingStrategy
    reducer::OptimalBranchingCore.AbstractReducer
    region_cache::RegionCache
end

# Main branch-and-reduce algorithm
function bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer)
    empty!(problem.buffer.branching_cache)
    cache = init_cache(problem, config.table_solver, config.measure, config.set_cover_solver, config.selector)
    ctx = SearchContext(problem.static, problem.stats, problem.buffer, problem.learned_clauses, problem.v2c, config, reducer, cache)
    return _bbsat!(ctx, problem.doms)
end

function _bbsat!(ctx::SearchContext, doms::Vector{DomainMask})
    if count_unfixed(doms) == 0
        return Result(true, copy(doms), copy(ctx.stats))
    end

    base_problem = TNProblem(ctx.static, doms, ctx.stats, ctx.buffer, ctx.learned_clauses, ctx.v2c)

    if is_two_sat(doms, ctx.static)
        solution = solve_2sat(base_problem)
        return Result(isnothing(solution) ? false : true, isnothing(solution) ? DomainMask[] : solution, copy(ctx.stats))
    end
    
    empty!(ctx.buffer.branching_cache)
    
    clauses, variables = findbest(ctx.region_cache, base_problem, ctx.config.measure, ctx.config.set_cover_solver, ctx.config.selector)
    # Handle failure case: no valid branching found
    isnothing(clauses) && (return Result(false, DomainMask[], copy(ctx.stats)))

    # All variable assignments in each branch are placed in the same decision level
    record_branch!(ctx.stats, length(clauses))

    @inbounds for i in 1:length(clauses)
        record_visit!(ctx.stats)
        # Propagate this branch on-demand
        subproblem_doms = probe_branch!(base_problem, ctx.buffer, doms, clauses[i], variables)
        # Recursively solve
        result = _bbsat!(ctx, copy(subproblem_doms))
        result.found && (return result)
    end
    return Result(false, DomainMask[], copy(ctx.stats))
end
