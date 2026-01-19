# ============================================================================
# Branch-and-Bound SAT Solver
#
# This module implements the core branching algorithm for solving SAT problems
# using tensor network representations. The algorithm combines:
# - Region-based branching with optimal branching rules
# - Gamma-1 reduction for exploiting forced assignments
# - CDCL fallback for small subproblems (Cube and Conquer)
# - 2-SAT detection and specialized solving
# ============================================================================

# ============================================================================
# OptimalBranchingCore Interface Extensions
# ============================================================================

"""
    probe_branch!(problem, buffer, base_doms, clause, variables) -> Vector{DomainMask}

Apply a branching clause to the current domain state and propagate constraints.
Returns the resulting domain state after propagation.
"""
@inline function probe_branch!(
    problem::TNProblem,
    buffer::SolverBuffer,
    base_doms::Vector{DomainMask},
    clause::Clause,
    variables::Vector{Int}
)
    return probe_assignment_core!(problem, buffer, base_doms, variables, clause.mask, clause.val)
end

"""
    OptimalBranchingCore.size_reduction(p, m, cl, variables) -> Number

Compute the measure reduction achieved by applying a clause.
Uses caching to avoid redundant propagation.
"""
function OptimalBranchingCore.size_reduction(
    p::TNProblem,
    m::AbstractMeasure,
    cl::Clause{UInt64},
    variables::Vector{Int}
)
    new_measure = get!(p.buffer.branching_cache, cl) do
        new_doms = probe_branch!(p, p.buffer, p.doms, cl, variables)
        @assert !has_contradiction(new_doms) "Contradiction found when probing branch $cl"
        measure_core(p.static, new_doms, m)
    end
    return measure(p, m) - new_measure
end

"""
    OptimalBranchingCore.optimal_branching_rule(table, variables, problem, m, solver) -> OptimalBranchingResult

Compute the optimal branching rule for NaiveBranch solver.
Filters out contradicting branches and computes branching complexity.
"""
function OptimalBranchingCore.optimal_branching_rule(
    table::BranchingTable,
    variables::Vector,
    problem::TNProblem,
    m::AbstractMeasure,
    solver::NaiveBranch
)
    candidates = OptimalBranchingCore.bit_clauses(table)
    valid_clauses = Clause{UInt64}[]
    size_reductions = Float64[]
    vars_int = Vector{Int}(variables)

    for candidate in candidates
        cl = first(candidate)
        new_doms = probe_branch!(problem, problem.buffer, problem.doms, cl, vars_int)
        has_contradiction(new_doms) && continue

        new_measure = measure_core(problem.static, new_doms, m)
        problem.buffer.branching_cache[cl] = new_measure
        push!(valid_clauses, cl)
        push!(size_reductions, Float64(measure(problem, m) - new_measure))
    end

    isempty(valid_clauses) && error("All branches lead to contradiction - problem is UNSAT")

    gamma = OptimalBranchingCore.complexity_bv(size_reductions)
    return OptimalBranchingCore.OptimalBranchingResult(DNF(valid_clauses), size_reductions, gamma)
end

# ============================================================================
# Search Context
# ============================================================================

"""
    SearchContext

Immutable context holding all solver state that remains constant during search.
This includes the constraint network, configuration, and solver resources.
"""
struct SearchContext
    static::ConstraintNetwork
    stats::BranchingStats
    buffer::SolverBuffer
    config::OptimalBranchingCore.BranchingStrategy
    reducer::OptimalBranchingCore.AbstractReducer
    region_cache::RegionCache
    target_vars::Vector{Int}
    cdcl_cutoff::Float64
    initial_active_tensors::Int
end

@inline function should_use_cdcl(ctx::SearchContext, doms::Vector{DomainMask})
    ctx.cdcl_cutoff >= 1.0 && return false
    current_active = count_active_tensors(ctx.static, doms)
    return current_active <= ctx.initial_active_tensors * ctx.cdcl_cutoff
end

# ============================================================================
# Reduction Phase
# ============================================================================

"""
    reduce_with_gamma_one!(ctx, doms, reducer) -> (new_doms, assignments, has_contradiction)

Exhaustively apply gamma=1 reductions until saturation.

**Optimized Algorithm:**
1. Modify `doms` in-place (no copying since γ=1 reductions are safe)
2. Use single TNProblem throughout
3. Sort once per outer iteration, continue scanning without re-sort
4. Early termination when no forced vars possible

Returns:
- `new_doms`: The reduced domain state (same as input `doms`, modified in-place)
- `assignments`: Empty vector (kept for API compatibility)
- `has_contradiction`: Whether a contradiction was encountered (should be false for γ=1)
"""
function reduce_with_gamma_one!(ctx::SearchContext, doms::Vector{DomainMask}, reducer::GammaOneReducer)
    # Empty assignments vector for API compatibility
    assignments = Vector{Tuple{Clause, Vector{Int}, Vector{DomainMask}, Vector{DomainMask}}}()
    
    # Use a single problem view - doms will be modified in-place
    problem = TNProblem(ctx.static, doms, ctx.stats, ctx.buffer)

    # Check only the first limit variables (or fewer if not available)
    sorted_vars = get_sorted_unfixed_vars(problem)
    isempty(sorted_vars) && return (doms, assignments, false)
    
    n_vars = length(sorted_vars)
    scan_limit = reducer.limit == 0 ? n_vars : min(n_vars, reducer.limit)
    
    for scan_pos in 1:scan_limit
        var_id = sorted_vars[scan_pos]
        # Skip if variable became fixed (from propagation of earlier reductions)
        is_fixed(doms[var_id]) && continue
        
        result = find_forced_assignment(ctx.region_cache, problem, var_id, ctx.config.measure)
        
        if !isnothing(result)
            clause, variables = result
            
            # Record statistics before modification
            old_unfixed = count_unfixed(doms)
            
            # Apply assignment in-place (no copying!)
            success = apply_assignment_inplace!(problem, ctx.buffer, doms, variables, clause.mask, clause.val)
            @assert success "Contradiction found when applying assignment"
            # Record statistics
            direct_vars = count_ones(clause.mask)
            total_vars_fixed = old_unfixed - count_unfixed(doms)
            record_reduction!(ctx.stats, direct_vars, total_vars_fixed - direct_vars)
            record_reduction_node!(ctx.stats)
        end
    end

    return (doms, assignments, false)
end

# ============================================================================
# CDCL Fallback (Cube and Conquer)
# ============================================================================

"""
    solve_with_cdcl(ctx, doms) -> Result

Convert the current problem state to CNF and solve with CDCL (Kissat).
Used as fallback when the problem has been sufficiently reduced.
"""
function solve_with_cdcl(ctx::SearchContext, doms::Vector{DomainMask})
    cnf, nvars = tn_to_cnf_with_doms(ctx.static, doms)

    @debug "CDCL fallback" unfixed_vars = count_unfixed(doms) total_vars = nvars nclauses = length(cnf)

    empty_count = count(isempty, cnf)
    empty_count > 0 && @warn "CDCL: Found $empty_count empty clauses"

    status, model, _ = solve_and_mine(cnf; nvars=nvars)

    @debug "CDCL result" status

    if status == :sat
        solution = copy(doms)
        for i in 1:nvars
            if !is_fixed(doms[i]) && model[i] != 0
                solution[i] = model[i] > 0 ? DM_1 : DM_0
            end
        end
        return Result(true, solution, copy(ctx.stats))
    elseif status == :unsat
        return Result(false, DomainMask[], copy(ctx.stats))
    else
        error("CDCL returned unknown status")
    end
end

# ============================================================================
# Main Branching Algorithm
# ============================================================================

"""
    bbsat!(problem, config, reducer; target_vars, cdcl_cutoff) -> Result

Main entry point for the branch-and-bound SAT solver.

# Arguments
- `problem::TNProblem`: The tensor network SAT problem
- `config::BranchingStrategy`: Branching configuration
- `reducer::AbstractReducer`: Reduction strategy

# Keyword Arguments
- `target_vars::Vector{Int}=Int[]`: Variables to fix (empty = all)
- `cdcl_cutoff::Float64=1.0`: Switch to CDCL when active_tensors <= initial * cutoff
# Returns
- `Result`: Solution result with found flag, solution domains, and statistics
"""
function bbsat!(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
    reducer::OptimalBranchingCore.AbstractReducer;
    target_vars::Vector{Int}=Int[],
    cdcl_cutoff::Float64=1.0
)
    empty!(problem.buffer.branching_cache)
    cache = init_cache(problem, config.table_solver, config.measure,
        config.set_cover_solver, config.selector)
    initial_active = count_active_tensors(problem.static, problem.doms)

    ctx = SearchContext(
        problem.static, problem.stats, problem.buffer,
        config, reducer, cache,
        target_vars, cdcl_cutoff, initial_active
    )
    return _bbsat!(ctx, problem.doms, 0)
end

"""
    is_solved(ctx, doms) -> Bool

Check if the problem is solved (all target variables fixed).
"""
@inline function is_solved(ctx::SearchContext, doms::Vector{DomainMask})
    if isempty(ctx.target_vars)
        return count_unfixed(doms) == 0
    else
        return all(v -> is_fixed(doms[v]), ctx.target_vars)
    end
end

"""
    _bbsat!(ctx, doms, depth) -> Result

Internal branching function with loop for single-branch cases.

The algorithm proceeds as follows:
1. Check termination conditions
2. Apply gamma-1 reductions (if using GammaOneReducer)
3. Check for CDCL cutoff or 2-SAT subproblem
4. Select branching variable and compute branches
5. If single branch (γ=1): apply and loop (no recursion)
6. If multi-branch: recursively solve each branch
"""
function _bbsat!(ctx::SearchContext, doms::Vector{DomainMask}, depth::Int)
    current_doms = doms
    
    # Main loop - handles single-branch cases without recursion
    while true
        # Check termination
        if is_solved(ctx, current_doms)
            record_sat_leaf!(ctx.stats)
            return Result(true, copy(current_doms), copy(ctx.stats))
        end

        # Reduction phase (modifies current_doms in-place)
        if ctx.reducer isa GammaOneReducer
            reduced_doms, _, has_contra = reduce_with_gamma_one!(ctx, current_doms, ctx.reducer)
            if has_contra
                record_unsat_leaf!(ctx.stats)
                return Result(false, DomainMask[], copy(ctx.stats))
            end
            current_doms = reduced_doms
            if is_solved(ctx, current_doms)
                record_sat_leaf!(ctx.stats)
                return Result(true, copy(current_doms), copy(ctx.stats))
            end
        end

        problem = TNProblem(ctx.static, current_doms, ctx.stats, ctx.buffer)

        # CDCL fallback
        if should_use_cdcl(ctx, current_doms)
            return solve_with_cdcl(ctx, current_doms)
        end

        # 2-SAT detection
        if is_two_sat(current_doms, ctx.static)
            solution = solve_2sat(problem)
            if isnothing(solution)
                return Result(false, DomainMask[], copy(ctx.stats))
            end
            return Result(true, solution, copy(ctx.stats))
        end

        # Variable selection and branching
        empty!(ctx.buffer.branching_cache)
        clauses, variables, gamma, table_info = findbest(ctx.region_cache, problem, ctx.config.measure, ctx.config.set_cover_solver, ctx.config.selector, depth)

        # Record γ, measure, and table size for analysis
        if !isnothing(gamma)
            record_gamma!(ctx.stats, gamma)
            record_measure!(ctx.stats, Float64(measure(problem, ctx.config.measure)))
            record_table_size!(ctx.stats, table_info.n_configs, table_info.n_vars)
        end

        if isnothing(clauses)
            record_unsat_leaf!(ctx.stats)
            return Result(false, DomainMask[], copy(ctx.stats))
        end

        # Single branch (γ=1): apply and continue loop (no recursion!)
        if length(clauses) == 1
            subproblem_doms = probe_branch!(problem, ctx.buffer, current_doms, clauses[1], variables)
            if has_contradiction(subproblem_doms)
                record_unsat_leaf!(ctx.stats)
                return Result(false, DomainMask[], copy(ctx.stats))
            end
            record_reduction_node!(ctx.stats)
            current_doms = copy(subproblem_doms)
            continue  # Loop instead of recurse
        end

        # Multi-branch: must recurse for each branch
        record_branching_node!(ctx.stats, length(clauses))

        @inbounds for i in 1:length(clauses)
            clause = clauses[i]
            subproblem_doms = probe_branch!(problem, ctx.buffer, current_doms, clause, variables)

            if has_contradiction(subproblem_doms)
                record_unsat_leaf!(ctx.stats)
                continue
            end

            direct_vars = count_ones(clause.mask)
            total_vars_fixed = count_unfixed(current_doms) - count_unfixed(subproblem_doms)
            record_child_explored!(ctx.stats, direct_vars, total_vars_fixed - direct_vars)

            result = _bbsat!(ctx, copy(subproblem_doms), depth + 1)
            if result.found
                return result
            end
        end

        return Result(false, DomainMask[], copy(ctx.stats))
    end
end
