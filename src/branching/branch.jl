@inline probe_branch!(cn::ConstraintNetwork, buffer::SolverBuffer, base_doms::Vector{DomainMask}, clause::Clause, variables::Vector{Int}, record_trail::Bool, level::Int) = probe_assignment_core!(cn, buffer, base_doms, variables, clause.mask, clause.val, record_trail, level)

function OptimalBranchingCore.size_reduction(p::TNProblem, m::AbstractMeasure, cl::Clause{UInt64}, variables::Vector{Int})
    if haskey(p.buffer.branching_cache, cl)
        new_measure = p.buffer.branching_cache[cl]
    else
        new_doms = probe_branch!(p.static, p.buffer, p.doms, cl, variables, false, 0)
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
    config::OptimalBranchingCore.BranchingStrategy
    reducer::OptimalBranchingCore.AbstractReducer
    region_cache::RegionCache
end

# Main branch-and-reduce algorithm
function bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer)
    empty!(problem.buffer.branching_cache)
    cache = init_cache(problem, config.table_solver, config.measure, config.set_cover_solver, config.selector)
    ctx = SearchContext(problem.static, problem.stats, problem.buffer, config, reducer, cache)
    return _bbsat!(ctx, problem.doms)
end

function _bbsat!(ctx::SearchContext, doms::Vector{DomainMask})
    if count_unfixed(doms) == 0
        return Result(true, copy(doms), copy(ctx.stats))
    end
    
    if is_two_sat(doms, ctx.static)
        solution = solve_2sat(TNProblem(ctx.static, doms, ctx.stats, ctx.buffer))
        return Result(isnothing(solution) ? false : true, isnothing(solution) ? DomainMask[] : solution, copy(ctx.stats))
    end
    
    empty!(ctx.buffer.branching_cache)
    
    temp_problem = TNProblem(ctx.static, doms, ctx.stats, ctx.buffer)
    clauses, variables = findbest(ctx.region_cache, temp_problem, ctx.config.measure, ctx.config.set_cover_solver, ctx.config.selector)

    # Handle failure case: no valid branching found
    isnothing(clauses) && (return Result(false, DomainMask[], copy(ctx.stats)))
    
    # Get parent level for backtracking
    parent_level = get_current_level(ctx.buffer)

    # All variable assignments in each branch are placed in the same decision level
    record_branch!(ctx.stats, length(clauses))

    @inbounds for i in 1:length(clauses)
        record_visit!(ctx.stats)
        # Create a new decision level for this branch
        new_level = new_decision_level!(ctx.buffer)
        # Propagate this branch on-demand with trail recording enabled
        subproblem_doms = probe_branch!(ctx.static, ctx.buffer, doms, clauses[i], variables, true, new_level)
        # Recursively solve
        result = _bbsat!(ctx, copy(subproblem_doms))
        result.found && return result
        # This branch failed, backtrack to parent before trying next clause
        if i < length(clauses)
            backtrack!(ctx.buffer, parent_level)
        end
    end

    # All branches failed, backtrack to parent level
    backtrack!(ctx.buffer, parent_level)
    return Result(false, DomainMask[], copy(ctx.stats))
end

