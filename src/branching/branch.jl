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

function OptimalBranchingCore.optimal_branching_rule(table::BranchingTable, variables::Vector, problem::TNProblem, m::AbstractMeasure, solver::NaiveBranch)
    candidates = OptimalBranchingCore.bit_clauses(table)

    # Collect valid branches (non-contradicting) and their size reductions
    valid_clauses = Clause{UInt64}[]
    size_reductions = Float64[]

    for candidate in candidates
        cl = first(candidate)
        # Probe this branch to check for contradictions
        new_doms = probe_branch!(problem, problem.buffer, problem.doms, cl, Vector{Int}(variables))

        if has_contradiction(new_doms)
            # Skip this branch - it leads to contradiction
            continue
        end

        # Calculate size reduction for valid branch
        new_measure = measure_core(problem.static, new_doms, m)
        problem.buffer.branching_cache[cl] = new_measure
        reduction = measure(problem, m) - new_measure

        push!(valid_clauses, cl)
        push!(size_reductions, Float64(reduction))
    end

    # Handle edge case: all branches lead to contradiction
    if isempty(valid_clauses)
        error("All branches lead to contradiction - problem is likely UNSAT")
    end

    γ = OptimalBranchingCore.complexity_bv(size_reductions)
    return OptimalBranchingCore.OptimalBranchingResult(DNF(valid_clauses), size_reductions, γ)
end

# the static parameters are not changed during the search
# L is the logger type - using type parameter allows compile-time dispatch





struct SearchContext{L<:AbstractLogger}
    static::ConstraintNetwork
    stats::BranchingStats
    buffer::SolverBuffer
    learned_clauses::Vector{ClauseTensor}
    v2c::Vector{Vector{Int}}
    config::OptimalBranchingCore.BranchingStrategy
    reducer::OptimalBranchingCore.AbstractReducer
    region_cache::RegionCache
    logger::L
end

function bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer;
    logger::AbstractLogger=NoLogger())
    empty!(problem.buffer.branching_cache)
    cache = init_cache(problem, config.table_solver, config.measure, config.set_cover_solver, config.selector)

    ctx = SearchContext(problem.static, problem.stats, problem.buffer, problem.learned_clauses, problem.v2c,
        config, reducer, cache, logger)

    return _bbsat!(ctx, problem.doms, 0)  # Start at depth 0
end



function _bbsat!(ctx::SearchContext, doms::Vector{DomainMask}, depth::Int)
    if count_unfixed(doms) == 0
        return Result(true, copy(doms), copy(ctx.stats))
    end

    base_problem = TNProblem(ctx.static, doms, ctx.stats, ctx.buffer, ctx.learned_clauses, ctx.v2c)

    if is_two_sat(doms, ctx.static)
        solution = solve_2sat(base_problem)
        return Result(isnothing(solution) ? false : true, isnothing(solution) ? DomainMask[] : solution, copy(ctx.stats))
    end

    empty!(ctx.buffer.branching_cache)

    # Initialize log for this decision
    new_log!(ctx.logger, depth)

    clauses, variables, region, support_size = findbest_with_region(ctx.region_cache, base_problem, ctx.config.measure, ctx.config.set_cover_solver, ctx.config.selector, depth)
    # Handle failure case: no valid branching found
    isnothing(clauses) && (return Result(false, DomainMask[], copy(ctx.stats)))


    # Log region statistics (computes boundary as vars connected outside region)
    log_region!(ctx.logger, region, compute_boundary_size(ctx.static, region, doms))
    log_support!(ctx.logger, support_size)
    log_branch_count!(ctx.logger, length(clauses))

    # OPTIMIZATION: Single branch = forced propagation, not a real decision
    # Apply directly without recursion overhead and without counting as a branch
    if length(clauses) == 1
        subproblem_doms = probe_branch!(base_problem, ctx.buffer, doms, clauses[1], variables)
        if has_contradiction(subproblem_doms)
            finish_log!(ctx.logger)
            return Result(false, DomainMask[], copy(ctx.stats))
        end
        # Continue with the forced assignment (tail-call like behavior)
        finish_log!(ctx.logger)
        return _bbsat!(ctx, copy(subproblem_doms), depth)  # Same depth - not a real decision
    end

    # All variable assignments in each branch are placed in the same decision level
    record_branch!(ctx.stats, length(clauses))

    base_unfixed = count_unfixed(doms)

    @inbounds for i in 1:length(clauses)
        record_visit!(ctx.stats)

        # Time propagation
        prop_start = time_ns()
        subproblem_doms = probe_branch!(base_problem, ctx.buffer, doms, clauses[i], variables)
        prop_time = time_ns() - prop_start
        log_prop_time!(ctx.logger, prop_time)


        # Log forced assignments (how many vars were fixed by propagation beyond the branch itself)
        new_unfixed = count_unfixed(subproblem_doms)

        branch_vars_set = count_ones(clauses[i].mask)
        forced = base_unfixed - new_unfixed - branch_vars_set
        log_forced_assignments!(ctx.logger, max(0, forced))

        # Check for contradiction BEFORE recursion
        if has_contradiction(subproblem_doms)
            continue
        end

        # Recursively solve
        result = _bbsat!(ctx, copy(subproblem_doms), depth + 1)
        result.found && (return result)
    end

    finish_log!(ctx.logger)
    return Result(false, DomainMask[], copy(ctx.stats))
end

# Helper to compute boundary size (vars in region connected to tensors outside region)
function compute_boundary_size(cn::ConstraintNetwork, region::Region, doms::Vector{DomainMask})
    region_tensor_set = Set(region.tensors)
    boundary_count = 0
    for var_id in region.vars
        is_fixed(doms[var_id]) && continue
        for tensor_id in cn.v2t[var_id]
            if tensor_id ∉ region_tensor_set
                boundary_count += 1
                break  # Count each var once
            end
        end
    end
    return boundary_count
end

