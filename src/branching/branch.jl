@inline probe_branch!(cn::ConstraintNetwork, buffer::SolverBuffer, base_doms::Vector{DomainMask}, clause::Clause, variables::Vector{Int}, record_trail::Bool=false, level::Int=0) = probe_assignment_core!(cn, buffer, base_doms, variables, clause.mask, clause.val, record_trail, level)

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
    if count_unfixed(doms) == 0 
        for lcl in ctx.buffer.learned_clauses
            satisfied = false
            for literal in lcl
                if doms[literal[1]] == literal[2]
                    satisfied = true
                    break
                end
            end
            if !satisfied
                @show lcl
            end
        end
        return Result(true, doms, copy(ctx.stats))
    end
    empty!(ctx.buffer.branching_cache)
    # Enter new decision level
    
    temp_problem = TNProblem(ctx.static, doms, ctx.stats, ctx.buffer)
    # @show ctx.buffer.trail
    # @show "-----"
    branch_result = findbest(ctx.region_cache, temp_problem, ctx.config.measure, ctx.config.set_cover_solver, ctx.config.selector)
    # @show ctx.buffer.trail

    # Handle failure case: no valid branching found
    isnothing(branch_result) && (return Result(false, DomainMask[], copy(ctx.stats)))
    
    # Get parent level for backtracking
    parent_level = get_current_level(ctx.buffer)
    
    # TODO: (draft version) Now this is ugly, but at least it's fast.
    # Handle 2-SAT case: findbest returns pre-propagated domains
    if branch_result isa Vector{Vector{DomainMask}}
        record_branch!(ctx.stats, length(branch_result))
        @inbounds for subproblem_doms in branch_result
            record_visit!(ctx.stats)
            result = _bbsat!(ctx, subproblem_doms)
            result.found && return result
            # No need to backtrack - subproblem_doms is independent
        end
    else
        # Handle normal case: findbest returns (clauses, variables)
        # Each variable assignment in probe_branch! will create its own decision level
        clauses, variables = branch_result
        record_branch!(ctx.stats, length(clauses))

        @inbounds for i in 1:length(clauses)
            record_visit!(ctx.stats)
            # Propagate this branch on-demand with trail recording enabled
            # Note: probe_branch! now creates a new decision level for each variable assignment
            subproblem_doms = probe_branch!(ctx.static, ctx.buffer, doms, clauses[i], variables, true, parent_level)
            # Must copy
            result = _bbsat!(ctx, copy(subproblem_doms))
            result.found && return result
            # This branch failed, backtrack to parent before trying next clause
            if i < length(clauses)
                backtrack!(ctx.buffer, parent_level)
            end
        end
    end

    # All branches failed, backtrack to parent level
    backtrack!(ctx.buffer, parent_level)
    return Result(false, DomainMask[], copy(ctx.stats))
end

