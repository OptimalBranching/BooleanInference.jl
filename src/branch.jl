function OptimalBranchingCore.branch_and_reduce(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
    reducer::OptimalBranchingCore.AbstractReducer,
    result_type::Type{TR};
    show_progress::Bool=false,
    tag::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[]
) where TR
    # Update max depth
    current_depth = length(tag)
    if current_depth > problem.ws.max_depth
        problem.ws.max_depth = current_depth
    end

    # Step 1: Check if problem is solved (all variables fixed)
    if is_solved(problem)
        @debug "problem is solved"
        cache_branch_solution!(problem)
        return one(result_type)
    end
    # Step 2: Try to reduce the problem
    @assert reducer isa NoReducer

    # Step 3: Select variables for branching
    variable = OptimalBranchingCore.select_variables(problem, config.measure, config.selector)

    # Step 4: Compute branching table
    tbl, variables = OptimalBranchingCore.branching_table(problem, config.table_solver, variable)

    # Check if table is empty (UNSAT - no valid configurations)
    if isempty(tbl.table)
        @debug "Empty branching table - UNSAT"
        return zero(result_type)
    end

    # Step 5: Compute optimal branching rule
    result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, config.measure, config.set_cover_solver)

    # @show result.γ
    # @show tbl
    # Step 6: Branch and recurse
    clauses = OptimalBranchingCore.get_clauses(result)
    @debug "A new branch-level search starts with $(length(clauses)) clauses: $(clauses)"

    # Record branching statistics
    problem.ws.total_branches += 1
    problem.ws.total_subproblems += length(clauses)
    # @show clauses

    # Use explicit loop instead of sum() to avoid closure allocation overhead
    accum = zero(result_type)

    @inbounds for (i, branch) in enumerate(clauses)
        show_progress && (OptimalBranchingCore.print_sequence(stdout, tag); println(stdout))
        @debug "branch=$branch, n_unfixed=$(problem.n_unfixed)"

        # Apply branch to get subproblem
        subproblem, local_value, changed_vars = OptimalBranchingCore.apply_branch(problem, branch, variables)

        @debug "local_value=$local_value, n_unfixed=$(subproblem.n_unfixed)"

        # If branch led to contradiction (UNSAT), skip this branch
        if local_value == 0 || subproblem.n_unfixed == 0 && any(dm -> dm.bits == 0x00, subproblem.doms)
            @debug "Skipping branch: local_value=$local_value, n_unfixed=$(subproblem.n_unfixed), has_contradiction=$(any(dm -> dm.bits == 0x00, subproblem.doms))"
            continue  # Skip to next branch instead of creating zero value
        end

        # Recursively solve subproblem
        # Use mutable tag buffer: push before recursion, pop after
        # This avoids allocating new arrays on each recursive call
        push!(tag, (i, length(clauses)))
        sub_result = OptimalBranchingCore.branch_and_reduce(subproblem, config, reducer, result_type; tag=tag, show_progress=show_progress)
        pop!(tag)

        # Combine results
        accum = accum + sub_result * result_type(local_value)
    end

    return accum
end

function OptimalBranchingCore.optimal_branching_rule(
    tbl::OptimalBranchingCore.BranchingTable,
    variables::Vector{T},
    problem::TNProblem,
    measure::OptimalBranchingCore.AbstractMeasure,
    solver::OptimalBranchingCore.AbstractSetCoverSolver
) where T
    candidates = OptimalBranchingCore.bit_clauses(tbl)
    return OptimalBranchingCore.greedymerge(candidates, problem, variables, measure)
end


function OptimalBranchingCore.apply_branch(
    problem::TNProblem,
    clause::OptimalBranchingCore.Clause{INT},
    variables::Vector{Int}
) where {INT<:Integer}
    # Use object pool to reduce allocations
    new_doms = get_doms_from_pool!(problem.ws, problem.doms)

    # Use BitVector for O(1) membership testing
    # Track which indices we modify for efficient cleanup
    changed_flags = problem.ws.changed_vars_flags
    changed_indices = problem.ws.changed_vars_indices
    empty!(changed_indices)

    # Apply clause: fix variables according to mask and values
    n_fixed = 0

    @inbounds for i in 1:length(variables)
        mask_bit = OptimalBranchingCore.readbit(clause.mask, i)
        if mask_bit == 1
            # This variable is fixed by the clause
            var_id = variables[i]
            bit_val = OptimalBranchingCore.readbit(clause.val, i)
            new_val = ifelse(bit_val == 1, DM_1, DM_0)

            old_bits = problem.doms[var_id].bits
            # Branchless: check if not fixed (bits == 0x03)
            if old_bits == 0x03
                new_doms[var_id] = new_val
                n_fixed += 1
                changed_flags[var_id] = true
                push!(changed_indices, var_id)
            end
        end
    end

    @debug "apply_branch: Fixed $n_fixed variables"

    # Apply propagation (unit propagation) with cached buffers from workspace
    propagated_doms = propagate(problem.static, new_doms, problem.ws)

    # Return new_doms to pool since we now have propagated_doms
    return_doms_to_pool!(problem.ws, new_doms)

    # Track additional variables that changed during propagation
    # Use BitVector for O(1) check instead of O(n) with ∉
    @inbounds for i in eachindex(propagated_doms)
        if propagated_doms[i].bits != problem.doms[i].bits && !changed_flags[i]
            changed_flags[i] = true
            push!(changed_indices, i)
        end
    end

    # Check for contradiction (all domains set to 0x00)
    # Use manual loop instead of any() for better performance
    has_contradiction = false
    @inbounds for dm in propagated_doms
        if dm.bits == 0x00
            has_contradiction = true
            break
        end
    end

    if has_contradiction
        # UNSAT: contradiction detected during propagation
        @debug "apply_branch: Contradiction detected during propagation"
        return (TNProblem(problem.static, fill(DomainMask(0x00), length(propagated_doms)), 0, problem.ws), 0, Int[])
    end

    # Count unfixed variables
    new_n_unfixed = count_unfixed(propagated_doms)

    @debug "apply_branch: n_unfixed: $(problem.n_unfixed) -> $new_n_unfixed"

    # Safety check: problem must have gotten smaller OR we fixed at least one variable
    if new_n_unfixed == problem.n_unfixed && n_fixed == 0
        @debug "apply_branch: No progress made (n_unfixed same and n_fixed=0)"
        return (TNProblem(problem.static, fill(DomainMask(0x00), length(propagated_doms)), 0, problem.ws), 0, Int[])
    end

    # Create new problem with updated domains
    new_problem = TNProblem(problem.static, propagated_doms, new_n_unfixed, problem.ws)

    # Clear only the flags we set (O(k) instead of O(n) where k = number of changed vars)
    @inbounds for idx in changed_indices
        changed_flags[idx] = false
    end

    return (new_problem, 1, Int[])  # local_value = 1 (no scoring for now)
end

function OptimalBranchingCore.reduce_problem(::Type{T}, problem::TNProblem, ::OptimalBranchingCore.NoReducer) where T
    return (problem, one(T))
end

# function reduce_problem(::Type{T}, problem::TNProblem, reducer::UnitPropagationReducer) where T
#     propagated = propagate(problem.static, problem.doms)

#     doms = problem.doms
#     changed = false
#     n_unfixed::Int = 0

#     @inbounds for i in eachindex(doms)
#         dm_new = propagated[i]
#         bits = dm_new.bits

#         if bits == 0x00
#             clear_region_cache!(problem)
#             return (TNProblem(problem.static, propagated, 0, problem.ws), zero(T))
#         end

#         changed |= bits != doms[i].bits
#         n_unfixed += is_fixed(dm_new) ? 0 : 1
#     end

#     if !changed
#         return (problem, one(T))
#     end

#     clear_region_cache!(problem)
#     return (TNProblem(problem.static, propagated, n_unfixed, problem.ws), one(T))
# end
