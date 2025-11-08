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
            record_solved_leaf!(stats, current_depth, problem.ws.current_path)
            @debug "problem is solved at depth $current_depth"
            cache_branch_solution!(problem)
            return one(result_type)
        end

        record_depth!(stats, current_depth)
        @debug "======= Decision Level: $(current_depth + 1) ======="
        # println("======= Decision Level: $(current_depth + 1) =======")
        # Step 2: Try to reduce the problem
        @assert reducer isa NoReducer

        # record branching time (only if detailed stats are enabled)
        has_detailed = !isnothing(stats.detailed)
        branching_start_time = has_detailed ? time_ns() : 0
        
        # Step 3: Select variables for branching
        variable = OptimalBranchingCore.select_variables(problem, config.measure, config.selector)
        
        # Record variable selection statistics and push to current path (only if tracking)
        record_variable_selection!(stats, variable, problem.n_unfixed, current_depth)
        needs_path_tracking(stats) && push!(problem.ws.current_path, variable)
        @debug "Variable $variable selected at depth $current_depth"

        # Step 4: Compute branching table
        tbl, variables = OptimalBranchingCore.branching_table(problem, config.table_solver, variable)

        # Check if table is empty (UNSAT - no valid configurations)
        if isempty(tbl.table)
            @debug "Empty branching table - UNSAT"
            has_detailed && record_branching_time!(stats, (time_ns() - branching_start_time) / 1e9)
            record_unsat_leaf!(stats, current_depth)
            # Pop current variable before returning (restore path for parent)
            needs_path_tracking(stats) && !isempty(problem.ws.current_path) && pop!(problem.ws.current_path)
            return zero(result_type)
        end

        # Step 5: Compute optimal branching rule
        result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, config.measure, config.set_cover_solver)
        
        # record branching time (only if detailed stats are enabled)
        has_detailed && record_branching_time!(stats, (time_ns() - branching_start_time) / 1e9)

        # @show tbl
        # Step 6: Branch and recurse
        clauses = OptimalBranchingCore.get_clauses(result)
        @debug "A new branch-level search starts with $(length(clauses)) clauses: $(clauses)"
        # @show clauses
        # Record branching statistics
        record_branch!(stats, length(clauses), current_depth)
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
            if local_value == 0 || subproblem.n_unfixed == 0 && has_contradiction(subproblem.doms)
                @debug "Skipping branch: local_value=$local_value, n_unfixed=$(subproblem.n_unfixed), has_contradiction=$(has_contradiction(subproblem.doms))"
                record_skipped_subproblem!(stats)
                record_unsat_leaf!(stats, current_depth + 1)
                continue  # Skip to next branch instead of creating zero value
            end

            # Recursively solve subproblem
            # Use mutable tag buffer: push before recursion, pop after
            # This avoids allocating new arrays on each recursive call
            push!(tag, (i, length(clauses)))
            # Save path length before recursion to restore after (only if tracking)
            path_length_before = needs_path_tracking(stats) ? length(problem.ws.current_path) : 0
            sub_result = OptimalBranchingCore.branch_and_reduce(subproblem, config, reducer, result_type; tag=tag, show_progress=show_progress)
            # Restore path to length before recursion (pop variables added during recursion)
            if needs_path_tracking(stats)
                while length(problem.ws.current_path) > path_length_before
                    pop!(problem.ws.current_path)
                end
            end
            pop!(tag)

            # Combine results
            accum = accum + sub_result * result_type(local_value)
            
            # Early exit: if we found a solution (accum > 0), return immediately
            # This ensures we only find one solution path
            if accum > zero(result_type)
                @debug "Found solution, early exit at depth $current_depth"
                needs_path_tracking(stats) && !isempty(problem.ws.current_path) && pop!(problem.ws.current_path)
                return accum
            end
        end

        # Pop current variable before returning (restore path for parent)
        needs_path_tracking(stats) && !isempty(problem.ws.current_path) && pop!(problem.ws.current_path)
        return accum
    finally
        clear_branch_cache!(problem.ws, Base.objectid(problem.doms))
    end
end

@inline function lookup_branch_cache(problem::TNProblem,
    clause::OptimalBranchingCore.Clause{INT},
    variables::Vector{Int}
) where {INT}
    ws = problem.ws
    doms_id = Base.objectid(problem.doms)
    inner = get(ws.branch_cache, doms_id, nothing)
    inner === nothing && return nothing
    key = (Base.objectid(variables), clause_key(clause))
    return get(inner, key, nothing)
end

@inline function store_branch_cache!(
    problem::TNProblem,
    clause::OptimalBranchingCore.Clause{INT},
    variables::Vector{Int},
    doms::Vector{DomainMask},
    n_unfixed::Int,
    local_value::Int
) where {INT}
    ws = problem.ws
    doms_id = Base.objectid(problem.doms)
    inner = get!(ws.branch_cache, doms_id) do
        Dict{Tuple{UInt, Any}, Any}()
    end
    key = (Base.objectid(variables), clause_key(clause))
    inner[key] = (doms=doms, n_unfixed=n_unfixed, local_value=local_value)
    return nothing
end

function OptimalBranchingCore.optimal_branching_rule(tbl::OptimalBranchingCore.BranchingTable, variables::Vector{T}, problem::TNProblem, measure::OptimalBranchingCore.AbstractMeasure, solver::OptimalBranchingCore.GreedyMerge) where T
    candidates = OptimalBranchingCore.bit_clauses(tbl)
    return OptimalBranchingCore.greedymerge(candidates, problem, variables, measure)
end

function OptimalBranchingCore.optimal_branching_rule(tbl::OptimalBranchingCore.BranchingTable{INT}, variables::Vector{T}, problem::TNProblem, measure::OptimalBranchingCore.AbstractMeasure, solver::OptimalBranchingCore.AbstractSetCoverSolver) where {INT<:Integer, T}
    candidates = OptimalBranchingCore.candidate_clauses(tbl)
    valid_clauses = Vector{OptimalBranchingCore.Clause{INT}}()
    reductions = Float64[]

    for clause in candidates
        reduction = Float64(OptimalBranchingCore.size_reduction(problem, measure, clause, variables))
        if isfinite(reduction) && reduction > 0
            push!(valid_clauses, clause)
            push!(reductions, reduction)
        end
    end

    if isempty(valid_clauses)
        empty_clauses = Vector{OptimalBranchingCore.Clause{INT}}()
        return OptimalBranchingCore.OptimalBranchingResult(
            OptimalBranchingCore.DNF(empty_clauses),
            Float64[],
            Inf,
        )
    end

    covered_mask = BitVector(undef, length(tbl.table))
    @inbounds for (idx, group) in pairs(tbl.table)
        covered_mask[idx] = any(valid_clauses) do clause
            any(config -> OptimalBranchingCore.covered_by(config, clause), group)
        end
    end

    if !all(covered_mask)
        if !any(covered_mask)
            empty_clauses = Vector{OptimalBranchingCore.Clause{INT}}()
            return OptimalBranchingCore.OptimalBranchingResult(
                OptimalBranchingCore.DNF(empty_clauses),
                Float64[],
                Inf,
            )
        end
        filtered_groups = tbl.table[findall(covered_mask)]
        tbl = OptimalBranchingCore.BranchingTable{INT}(tbl.bit_length, filtered_groups)
    end

    return OptimalBranchingCore.minimize_γ(tbl, valid_clauses, reductions, solver)
end

function OptimalBranchingCore.optimal_branching_rule(
    tbl::OptimalBranchingCore.BranchingTable{INT},
    variables::Vector{T},
    problem::TNProblem,
    measure::OptimalBranchingCore.AbstractMeasure,
    solver::OptimalBranchingCore.NaiveBranch
) where {INT<:Integer, T}
    return invoke(
        OptimalBranchingCore.optimal_branching_rule,
        Tuple{
            OptimalBranchingCore.BranchingTable,
            Vector,
            OptimalBranchingCore.AbstractProblem,
            OptimalBranchingCore.AbstractMeasure,
            OptimalBranchingCore.NaiveBranch,
        },
        tbl,
        variables,
        problem,
        measure,
        solver,
    )
end

# Apply a clause to domain masks, fixing variables according to the clause's mask and values. Returns the number of variables that were fixed.
function apply_clause_to_doms!(new_doms::Vector{DomainMask}, clause::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}, original_doms::Vector{DomainMask}, changed_flags::BitVector, changed_indices::Vector{Int}) where {INT<:Integer}
    n_fixed = 0

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
            end
        end
    end

    return n_fixed
end

function OptimalBranchingCore.apply_branch(
    problem::TNProblem,
    clause::OptimalBranchingCore.Clause{INT},
    variables::Vector{Int}
) where {INT<:Integer}
    if (cached = lookup_branch_cache(problem, clause, variables)) !== nothing
        subproblem = TNProblem(problem.static, cached.doms, cached.n_unfixed, problem.ws)
        return (subproblem, cached.local_value, Int[])
    end

    new_doms = copy(problem.doms)

    changed_flags = problem.ws.changed_vars_flags  # BitVector: tracking variable changes
    changed_indices = problem.ws.changed_vars_indices
    empty!(changed_indices)

    # Apply clause: fix variables according to mask and values
    n_fixed = apply_clause_to_doms!(new_doms, clause, variables, problem.doms, changed_flags, changed_indices)

    # @debug "apply_branch: Clause $(clause) Fixed $n_fixed variables"

    propagated_doms = propagate(problem.static, new_doms, changed_indices, problem.ws)

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
        store_branch_cache!(problem, clause, variables, doms_zero, problem.n_unfixed, 0)
        return (TNProblem(problem.static, doms_zero, problem.n_unfixed, problem.ws), 0, Int[])
    end

    # Count unfixed variables
    new_n_unfixed = count_unfixed(propagated_doms)

    @debug "apply_branch: Clause $(clause) n_unfixed: $(problem.n_unfixed) -> $new_n_unfixed"

    # Safety check: problem must have gotten smaller OR we fixed at least one variable
    if new_n_unfixed == problem.n_unfixed && n_fixed == 0
        @debug "apply_branch: No progress made (n_unfixed same and n_fixed=0)"
        doms_zero = fill(DM_NONE, length(propagated_doms))
        store_branch_cache!(problem, clause, variables, doms_zero, 0, 0)
        return (TNProblem(problem.static, doms_zero, 0, problem.ws), 0, Int[])
    end
    
    new_problem = TNProblem(problem.static, propagated_doms, new_n_unfixed, problem.ws)

    @inbounds for idx in changed_indices
        changed_flags[idx] = false
    end

    store_branch_cache!(problem, clause, variables, propagated_doms, new_n_unfixed, 1)
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
