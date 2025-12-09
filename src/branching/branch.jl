@inline probe_branch!(cn::ConstraintNetwork, buffer::SolverBuffer, base_doms::Vector{DomainMask}, clause::Clause, variables::Vector{Int}) = probe_assignment_core!(cn, buffer, base_doms, variables, clause.mask, clause.val)

function OptimalBranchingCore.size_reduction(p::TNProblem, m::AbstractMeasure, cl::Clause{UInt64}, variables::Vector{Int})
    if haskey(p.buffer.branching_cache, cl)
        newdoms = p.buffer.branching_cache[cl]
    else
        newdoms = probe_branch!(p.static, p.buffer, p.doms, cl, variables)
        p.buffer.branching_cache[cl] = copy(newdoms)
    end
    # @assert !has_contradiction(newdoms) "Contradiction found when probing branch $cl"
    r = measure(p, m) - measure_core(p.static, newdoms, m)
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
    count_unfixed(doms) == 0 && return Result(true, doms, copy(ctx.stats))

    empty!(ctx.buffer.branching_cache)
    
    temp_problem = TNProblem(ctx.static, doms, ctx.stats, ctx.buffer)
    
    subproblem_doms_list = findbest(ctx.region_cache, temp_problem, ctx.config.measure, ctx.config.set_cover_solver, ctx.config.selector)
    # @show ctx.region_cache
    isempty(subproblem_doms_list) && return Result(false, DomainMask[], copy(ctx.stats))
    
    record_branch!(ctx.stats, length(subproblem_doms_list))
    @inbounds for subproblem_doms in subproblem_doms_list
        record_visit!(ctx.stats)
        result = _bbsat!(ctx, subproblem_doms)
        result.found && return result
    end
    
    return Result(false, DomainMask[], copy(ctx.stats))
end