# Main branch-and-reduce algorithm and branch application logic

# Apply a clause to domain masks, fixing variables according to the clause's mask and values
# Two versions: one for evaluate (lightweight), one for commit (with trail/tracking)

# Lightweight version for evaluation - just applies the clause without tracking
function apply_clause_to_doms_eval!(new_doms::Vector{DomainMask}, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}, original_doms::Vector{DomainMask}, changed_indices::Vector{Int}) where {INT<:Integer}
    n_fixed = 0

    @inbounds for i in 1:length(variables)
        mask_bit = OptimalBranchingCore.readbit(clause.mask, i)
        if mask_bit == 1
            # This variable is fixed by the clause
            var_id = variables[i]
            bit_val = OptimalBranchingCore.readbit(clause.val, i)
            new_val = ifelse(bit_val == 1, DM_1, DM_0)

            old_dm = original_doms[var_id]
            if old_dm == DM_BOTH
                new_doms[var_id] = new_val
                n_fixed += 1
                push!(changed_indices, var_id)
            end
        end
    end

    return n_fixed
end

# Full version for commit - collects assignments for caching
function apply_clause_to_doms!(new_doms::Vector{DomainMask}, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}, original_doms::Vector{DomainMask}, changed_flags::BitVector, changed_indices::Vector{Int}) where {INT<:Integer}
    n_fixed = 0
    assignments = Tuple{Int,Bool}[]

    @inbounds for i in 1:length(variables)
        mask_bit = OptimalBranchingCore.readbit(clause.mask, i)
        if mask_bit == 1
            # This variable is fixed by the clause
            var_id = variables[i]
            bit_val = OptimalBranchingCore.readbit(clause.val, i)
            new_val = ifelse(bit_val == 1, DM_1, DM_0)

            old_dm = original_doms[var_id]
            if old_dm == DM_BOTH
                new_doms[var_id] = new_val
                n_fixed += 1
                changed_flags[var_id] = true
                push!(changed_indices, var_id)
                push!(assignments, (var_id, bit_val == 1))
            end
        end
    end

    return (n_fixed, assignments)
end

# Evaluate a branching clause (trial evaluation for size reduction)
# Returns (subproblem, local_value, changed_vars)
function evaluate_branch(problem::TNProblem, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}, temp_doms::Vector{DomainMask}) where {INT<:Integer}
    # Check cache first
    if (cached = lookup_branch_cache(problem, clause, variables)) !== nothing
        subproblem = TNProblem(problem.static, cached.doms, cached.n_unfixed, problem.ws)
        return (subproblem, cached.local_value, Int[])
    end

    # Use pre-allocated buffer
    copyto!(temp_doms, problem.doms)
    new_doms = temp_doms

    # Use a temporary changed_indices vector (no need to track flags)
    changed_indices = Int[]

    # Apply clause: fix variables according to mask and values (lightweight version)
    n_fixed = apply_clause_to_doms_eval!(new_doms, clause, variables, problem.doms, changed_indices)

    # Propagate without trail recording (to save memory)
    propagated_doms = propagate(problem.static, new_doms, changed_indices, problem.ws, nothing, 0, nothing)

    if has_contradiction(propagated_doms)
        # UNSAT: contradiction detected
        @debug "evaluate_branch: Contradiction detected"
        doms_zero = fill(DM_NONE, length(propagated_doms))
        store_branch_cache!(problem, clause, variables, doms_zero, problem.n_unfixed, 0, Tuple{Int,Bool}[])
        return (TNProblem(problem.static, doms_zero, problem.n_unfixed, problem.ws), 0, Int[])
    end

    # Count unfixed variables
    new_n_unfixed = count_unfixed(propagated_doms)

    # Safety check
    if new_n_unfixed == problem.n_unfixed && n_fixed == 0
        @debug "evaluate_branch: No progress made"
        doms_zero = fill(DM_NONE, length(propagated_doms))
        store_branch_cache!(problem, clause, variables, doms_zero, 0, 0, Tuple{Int,Bool}[])
        return (TNProblem(problem.static, doms_zero, 0, problem.ws), 0, Int[])
    end

    new_problem = TNProblem(problem.static, propagated_doms, new_n_unfixed, problem.ws)

    # Compute assignments for caching (only when we need to cache)
    assignments = Tuple{Int,Bool}[]
    @inbounds for i in 1:length(variables)
        mask_bit = OptimalBranchingCore.readbit(clause.mask, i)
        if mask_bit == 1
            var_id = variables[i]
            if problem.doms[var_id] == DM_BOTH
                bit_val = OptimalBranchingCore.readbit(clause.val, i)
                push!(assignments, (var_id, bit_val == 1))
            end
        end
    end

    # Store in cache (without trail entries to save memory)
    store_branch_cache!(problem, clause, variables, propagated_doms, new_n_unfixed, 1, assignments)

    return (new_problem, 1, Int[])
end

# Rebuild trail by re-executing the branch application with trail recording
function rebuild_trail!(problem::TNProblem, cached::BranchCacheEntry, temp_doms::Vector{DomainMask})
    trail = problem.ws.trail
    current_level = isempty(trail.stack) ? 0 : trail.stack[end].level
    decision_level = current_level + 1

    # Apply clause assignments to temp_doms
    copyto!(temp_doms, problem.doms)
    changed_flags = problem.ws.changed_vars_flags
    changed_indices = problem.ws.changed_vars_indices
    empty!(changed_indices)

    # Apply cached assignments
    for (var_id, value) in cached.assignments
        if problem.doms[var_id] == DM_BOTH
            temp_doms[var_id] = value ? DM_1 : DM_0
            changed_flags[var_id] = true
            push!(changed_indices, var_id)
            # Record decision to trail
            assign_var!(trail, var_id, value, decision_level, nothing)
        end
    end

    # Re-run propagation with trail recording
    propagate(problem.static, temp_doms, changed_indices, problem.ws, trail, decision_level)

    # Clear changed flags
    @inbounds for idx in changed_indices
        changed_flags[idx] = false
    end

    return nothing
end

# Commit a branching decision by applying a cached branch evaluation
# Assumes the branch was already evaluated by evaluate_branch() and cached
# Returns (subproblem, local_value, changed_vars)
function commit_branch(problem::TNProblem, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}, temp_doms::Vector{DomainMask}; record_trail::Bool=true) where {INT<:Integer}
    # Get cached result (should always exist since size_reduction already called evaluate_branch)
    cached = lookup_branch_cache(problem, clause, variables)

    if isnothing(cached)
        # Fallback: if not cached, call evaluate_branch to compute and cache it
        @debug "commit_branch: cache miss, calling evaluate_branch"
        evaluate_branch(problem, clause, variables, temp_doms)
        cached = lookup_branch_cache(problem, clause, variables)
        @assert cached !== nothing "Cache should exist after evaluate_branch"
    end

    record_trail && rebuild_trail!(problem, cached, temp_doms)

    subproblem = TNProblem(problem.static, cached.doms, cached.n_unfixed, problem.ws)
    return (subproblem, cached.local_value, Int[])
end

# Main branch-and-reduce algorithm
function OptimalBranchingCore.branch_and_reduce(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
    reducer::OptimalBranchingCore.AbstractReducer,
    result_type::Type{TR};
    show_progress::Bool=false,
    tag::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[]
) where TR
    try
        stats = problem.ws.branch_stats
        current_depth = length(tag)

        # Step 1: Check if problem is solved (all variables fixed)
        if is_solved(problem)
            record_solved_leaf!(stats, current_depth, needs_path_tracking(stats) ? problem.ws.trail : nothing)
            @debug "problem is solved at depth $current_depth"
            cache_branch_solution!(problem)
            return one(result_type)
        end

        record_depth!(stats, current_depth)
        @debug "======= Decision Level: $(current_depth + 1) ======="
        # Step 2: Try to reduce the problem
        @assert reducer isa NoReducer

        # record branching time (only if detailed stats are enabled)
        has_detailed = !isnothing(stats.detailed)
        branching_start_time = has_detailed ? time_ns() : 0

        # Step 3: Select variables for branching
        variable = OptimalBranchingCore.select_variables(problem, config.measure, config.selector)

        # Record variable selection statistics
        record_variable_selection!(stats, variable, problem.n_unfixed, current_depth)
        @debug "Variable $variable selected at depth $current_depth"

        # Step 4: Compute branching table
        tbl, variables = OptimalBranchingCore.branching_table(problem, config.table_solver, variable)

        # Check if table is empty (UNSAT - no valid configurations)
        if isempty(tbl.table)
            @debug "Empty branching table - UNSAT"
            has_detailed && record_branching_time!(stats, (time_ns() - branching_start_time) / 1e9)
            record_unsat_leaf!(stats, current_depth)
            return zero(result_type)
        end

        # Step 5: Compute optimal branching rule
        result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, config.measure, config.set_cover_solver)

        # record branching time (only if detailed stats are enabled)
        has_detailed && record_branching_time!(stats, (time_ns() - branching_start_time) / 1e9)

        # Step 6: Branch and recurse
        clauses = OptimalBranchingCore.get_clauses(result)
        @debug "A new branch-level search starts with $(length(clauses)) clauses: $(clauses)"
        # Record branching statistics
        record_branch!(stats, length(clauses), current_depth)

        accum = zero(result_type)
        @inbounds for (i, branch) in enumerate(clauses)
            show_progress && (OptimalBranchingCore.print_sequence(stdout, tag); println(stdout))
            @debug "branch=$branch, n_unfixed=$(problem.n_unfixed)"

            # Save trail state before applying branch
            trail_level_before = length(problem.ws.trail.level_start)
            trail_size_before = length(problem.ws.trail.stack)

            # Commit branch to get subproblem (record_trail=true for real branching decisions)
            subproblem, local_value, _ = commit_branch(problem, branch, variables, problem.ws.temp_doms; record_trail=true)

            @debug "local_value=$local_value, n_unfixed=$(subproblem.n_unfixed)"
            @show problem.ws.trail

            # If branch led to contradiction (UNSAT), skip this branch
            if local_value == 0 || subproblem.n_unfixed == 0 && has_contradiction(subproblem.doms)
                @debug "Skipping branch: local_value=$local_value, n_unfixed=$(subproblem.n_unfixed), has_contradiction=$(has_contradiction(subproblem.doms))"
                record_skipped_subproblem!(stats)
                record_unsat_leaf!(stats, current_depth + 1)
                # Backtrack trail to before this branch
                backtrack_trail!(problem.ws.trail, trail_level_before, trail_size_before)
                continue  # Skip to next branch instead of creating zero value
            end

            # Recursively solve subproblem
            # Use mutable tag buffer: push before recursion, pop after
            # This avoids allocating new arrays on each recursive call
            push!(tag, (i, length(clauses)))
            sub_result = OptimalBranchingCore.branch_and_reduce(subproblem, config, reducer, result_type; tag=tag, show_progress=show_progress)
            pop!(tag)

            # Backtrack trail after recursion (even if solution found, for next branch)
            backtrack_trail!(problem.ws.trail, trail_level_before, trail_size_before)

            # Combine results
            accum = accum + sub_result * result_type(local_value)

            # Early exit: if we found a solution (accum > 0), return immediately
            # This ensures we only find one solution path
            if accum > zero(result_type)
                @debug "Found solution, early exit at depth $current_depth"
                return accum
            end
        end

        return accum
    finally
        clear_branch_cache!(problem.ws, Base.objectid(problem.doms))
    end
end
