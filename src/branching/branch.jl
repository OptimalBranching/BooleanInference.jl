@inline probe_branch!(cn::ConstraintNetwork, buffer::SolverBuffer, base_doms::Vector{DomainMask}, clause::Clause, variables::Vector{Int}) = probe_assignment_core!(cn, buffer, base_doms, variables, clause.mask, clause.val)

function OptimalBranchingCore.size_reduction(p::TNProblem, m::AbstractMeasure, cl::Clause{UInt64}, variables::Vector{Int})
    if haskey(p.buffer.branching_cache, cl)
        new_measure = p.buffer.branching_cache[cl]
    else
        new_doms = probe_branch!(p.static, p.buffer, p.doms, cl, variables)
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
    count_unfixed(doms) == 0 && return Result(true, doms, copy(ctx.stats))

    empty!(ctx.buffer.branching_cache)

    temp_problem = TNProblem(ctx.static, doms, ctx.stats, ctx.buffer)

    branch_result = findbest(ctx.region_cache, temp_problem, ctx.config.measure, ctx.config.set_cover_solver, ctx.config.selector)

    # Handle failure case: no valid branching found
    isnothing(branch_result) && return Result(false, DomainMask[], copy(ctx.stats))

    # Handle 2-SAT case: findbest returns pre-propagated domains
    if branch_result isa Vector{Vector{DomainMask}}
        record_branch!(ctx.stats, length(branch_result))
        @inbounds for subproblem_doms in branch_result
            record_visit!(ctx.stats)
            result = _bbsat!(ctx, subproblem_doms)
            result.found && return result
        end
    else
        # Handle normal case: findbest returns (clauses, variables)
        # Propagate on-demand for each clause when needed
        clauses, variables = branch_result
        record_branch!(ctx.stats, length(clauses))
        @inbounds for i in 1:length(clauses)
            record_visit!(ctx.stats)
            # Propagate this branch on-demand
            subproblem_doms = probe_branch!(ctx.static, ctx.buffer, doms, clauses[i], variables)
            # Copy to avoid aliasing with buffer.scratch_doms
            result = _bbsat!(ctx, copy(subproblem_doms))
            result.found && return result
        end
    end

    return Result(false, DomainMask[], copy(ctx.stats))
end