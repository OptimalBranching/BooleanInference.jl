# Main branch-and-reduce algorithm and branch application logic

# Apply a clause to domain masks, fixing variables according to the clause's mask and values
# Returns (n_fixed, assignments) where assignments is a vector of (var_id, value::Bool) tuples
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
            # Branchless: check if not fixed (bits == 0x03)
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

# Apply a branching clause to the problem, returning a new subproblem
# record_trail: if true, record assignments to trail (for real branching decisions)
function apply_branch!(problem::TNProblem, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}, temp_doms::Vector{DomainMask}; record_trail::Bool=false) where {INT<:Integer}
    if (cached = lookup_branch_cache(problem, clause, variables)) !== nothing
        # If this is a real branch (not trial evaluation), we need to record to trail
        if record_trail && haskey(cached, :assignments)
            # Replay the branch application with trail recording
            # This ensures both branching decisions and propagation results are recorded
            trail = problem.ws.trail
            current_level = isempty(trail.stack) ? 0 : trail.stack[end].level
            decision_level = current_level + 1

            # Record branching decisions
            for (var_id, value) in cached.assignments
                assign_var!(trail, var_id, value, decision_level, nothing)
            end

            # Re-execute propagate to record propagation results to trail
            # We already have the final doms from cache, but we need to run propagate
            # to record the intermediate assignments to trail
            copyto!(temp_doms, problem.doms)

            # Apply the assignments to temp_doms
            for (var_id, value) in cached.assignments
                temp_doms[var_id] = value ? DM_1 : DM_0
            end

            # Find changed variables
            changed_vars = [var_id for (var_id, _) in cached.assignments]

            # Run propagate with trail recording
            _ = propagate(problem.static, temp_doms, changed_vars, problem.ws, trail, decision_level)
        end

        subproblem = TNProblem(problem.static, cached.doms, cached.n_unfixed, problem.ws)
        return (subproblem, cached.local_value, Int[])
    end

    # Use pre-allocated buffer instead of copy(problem.doms)
    copyto!(temp_doms, problem.doms)
    new_doms = temp_doms

    changed_flags = problem.ws.changed_vars_flags  # BitVector: tracking variable changes
    changed_indices = problem.ws.changed_vars_indices
    empty!(changed_indices)

    # Apply clause: fix variables according to mask and values
    n_fixed, assignments = apply_clause_to_doms!(new_doms, clause, variables, problem.doms, changed_flags, changed_indices)

    # @debug "apply_branch: Clause $(clause) Fixed $n_fixed variables"

    # Record branching decisions to trail BEFORE propagation (if this is a real branch)
    # For trial evaluation, don't record to trail at all
    if record_trail
        trail = problem.ws.trail
        # Create new decision level (increment from the current level)
        current_level = isempty(trail.stack) ? 0 : trail.stack[end].level
        decision_level = current_level + 1
        # Record branching decisions (reason = nothing for decision variables)
        for (var_id, value) in assignments
            assign_var!(trail, var_id, value, decision_level, nothing)
        end
        # Propagate with the new decision level and record to trail
        propagated_doms = propagate(problem.static, new_doms, changed_indices, problem.ws, trail, decision_level)
    else
        # For trial evaluation (not real branching), don't record to trail
        propagated_doms = propagate(problem.static, new_doms, changed_indices, problem.ws, nothing, 0)
    end

    @inbounds for i in eachindex(propagated_doms)
        if bits(propagated_doms[i]) != bits(problem.doms[i]) && !changed_flags[i]
            changed_flags[i] = true
            push!(changed_indices, i)
        end
    end

    if has_contradiction(propagated_doms)
        # UNSAT: contradiction detected during propagation
        @debug "apply_branch: Clause $(clause) Contradiction detected during propagation"
        doms_zero = fill(DM_NONE, length(propagated_doms))
        store_branch_cache!(problem, clause, variables, doms_zero, problem.n_unfixed, 0, Tuple{Int,Bool}[])
        return (TNProblem(problem.static, doms_zero, problem.n_unfixed, problem.ws), 0, Int[])
    end

    # Count unfixed variables
    new_n_unfixed = count_unfixed(propagated_doms)

    @debug "apply_branch: Clause $(clause) n_unfixed: $(problem.n_unfixed) -> $new_n_unfixed"

    # Safety check: problem must have gotten smaller OR we fixed at least one variable
    if new_n_unfixed == problem.n_unfixed && n_fixed == 0
        @debug "apply_branch: No progress made (n_unfixed same and n_fixed=0)"
        doms_zero = fill(DM_NONE, length(propagated_doms))
        store_branch_cache!(problem, clause, variables, doms_zero, 0, 0, Tuple{Int,Bool}[])
        return (TNProblem(problem.static, doms_zero, 0, problem.ws), 0, Int[])
    end

    new_problem = TNProblem(problem.static, propagated_doms, new_n_unfixed, problem.ws)

    @inbounds for idx in changed_indices
        changed_flags[idx] = false
    end

    store_branch_cache!(problem, clause, variables, propagated_doms, new_n_unfixed, 1, assignments)
    return (new_problem, 1, Int[])  # local_value = 1 (no scoring for now)
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

            # Apply branch to get subproblem (record_trail=true for real branching decisions)
            subproblem, local_value, _ = apply_branch!(problem, branch, variables, problem.ws.temp_doms; record_trail=true)

            @debug "local_value=$local_value, n_unfixed=$(subproblem.n_unfixed)"
            # @show problem.ws.trail

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
