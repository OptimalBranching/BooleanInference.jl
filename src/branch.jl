function OptimalBranchingCore.apply_branch(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, clause::Clause{INT}, vertices::Vector{T}) where {INT<:Integer,T<:Integer}
    bs_new, aedges = decide_literal(bs, p, vertices, clause)
    return deduction_reduce(p, bs_new, aedges)
end

# Try to finish by enumerating assignments for up to 2 undecided variables
function _finish_with_up_to_two(problem::BooleanInferenceProblem, bs::AbstractBranchingStatus, m::AbstractMeasure, stats::SearchStatistics)
    undecided_vars = [i for i in 1:problem.literal_num if readbit(bs.decided_mask, i) == 0]
    n = length(undecided_vars)
    if n == 0
        return BranchResult(true, bs)
    end
    n > 2 && return BranchResult(false, bs)
    mask = (Int(1) << n) - 1
    for val in 0:(1 << n) - 1
        bs_try = OptimalBranchingCore.apply_branch(problem, bs, Clause(mask, val), undecided_vars)
        stopped, res = check_stopped(bs_try, m, stats)
        if stopped && res
            return BranchResult(true, bs_try)
        end
    end
    return BranchResult(false, bs)
end

function OptimalBranchingCore.branch_and_reduce(problem::BooleanInferenceProblem, bs::AbstractBranchingStatus, config::BranchingStrategy, reducer::AbstractReducer; depth::Int=0, stats::SearchStatistics=SearchStatistics())
    # Track search depth
    update_max_depth!(stats, depth)
    increment_nodes!(stats)
    
    # Debug logging
    @dbg DEBUG_BASIC depth "BRANCH" "enter branch_and_reduce (depth: $(depth))"
    debug_branching_status(bs, problem, depth)
    
    # Determines if search should terminate
    stopped, res = check_stopped(bs, config.measure, stats)
    if stopped 
        @dbg DEBUG_BASIC depth "RESULT" (res ? "search stop: sat" : "search stop: unsat")
        return BranchResult(res, bs)
    end

    # If there are at most two undecided variables globally, finish by enumeration
    result2 = _finish_with_up_to_two(problem, bs, config.measure, stats)
    if result2.success 
        return result2
    end

    # If every active edge has ≤ 2 undecided variables, reduce to 2-SAT and solve
    @dbg DEBUG_DETAILED depth "2SAT" "try 2-SAT reduction"
    result2sat = _try_2sat(problem, bs, config.measure, stats)
    if result2sat.success 
        @dbg DEBUG_BASIC depth "2SAT" "2-SAT reduction success"
        return result2sat
    end

    # Branch the problem
    @dbg DEBUG_DETAILED depth "BRANCH" "start branching"
    
    # Select a subset of variables
    subbip = select_variables(problem, bs, config.measure, config.selector)
    @dbg DEBUG_VERBOSE depth "VARS" "selected vars: $(subbip.vs)"
    
    # Compute the BranchingTable
    tbl = branching_table(problem, bs, config.table_solver, subbip)
    if iszero(tbl.bit_length)
        @dbg DEBUG_DETAILED depth "BACKTRACK" "empty branching table, backtrack"
        return BranchResult(false, bs)
    end

    # Compute the optimal branching rule
    result = optimal_branching_rule(tbl, subbip.vs, bs, problem, config.measure, config.set_cover_solver)
    branches = OptimalBranchingCore.get_clauses(result)
    @dbg DEBUG_DETAILED depth "BRANCH" "generated $(length(branches)) branches"
    
    for (i, branch) in enumerate(branches)
        increment_branches!(stats)
        @dbg DEBUG_VERBOSE depth "TRY" "try branch $(i)/$(length(branches)): $(branch)"
        bs_new = apply_branch(problem, bs, branch, subbip.vs)
        
        branch_result = branch_and_reduce(problem, bs_new, config, reducer; depth=depth+1, stats=stats)
        
        if branch_result.success
            @dbg DEBUG_BASIC depth "SUCCESS" "branch $(i) leads to solution"
            return branch_result
        else
            @dbg DEBUG_VERBOSE depth "FAIL" "branch $(i) failed"
        end
    end
    
    @dbg DEBUG_BASIC depth "BACKTRACK" "all branches failed, backtrack"
    return BranchResult(false, bs)
end

"""
    check_stopped(bs::AbstractBranchingStatus, m::AbstractMeasure, stats::SearchStatistics)

Check whether the search should stop.

Returns (stopped::Bool, result::Bool) where result is true for satisfiable.
"""
function check_stopped(bs::AbstractBranchingStatus, m::AbstractMeasure, stats::SearchStatistics)
    # all constraints satisfied
    if all(bs.undecided_literals .== -1)
        increment_satisfiable!(stats)
        return true, true
    end
    # some constraint unsatisfied
    if any(bs.undecided_literals .== 0)
        increment_unsatisfiable!(stats)
        return true, false
    end
    # continue
    return false, false
end


function OptimalBranchingCore.optimal_branching_rule(table::BranchingTable, variables::Vector, bs::AbstractBranchingStatus, p::BooleanInferenceProblem, m::AbstractMeasure, solver::AbstractSetCoverSolver)
    candidates = OptimalBranchingCore.bit_clauses(table)
    return OptimalBranchingCore.greedymerge(candidates, p, bs, variables, m)
end

"""
    greedymerge(cls, problem, bs, variables, m)

Greedy clause merging algorithm for optimal branching rule computation.

This function implements a greedy algorithm that merges clauses to find an optimal 
branching rule. It works by iteratively finding pairs of clauses that can be merged
and checking if the merged clause provides better complexity reduction.

# Arguments
- `cls`: Vector of clause groups, where each group contains clauses to be considered
- `problem`: The boolean inference problem instance
- `bs`: Current branching status
- `variables`: Variables involved in the subproblem
- `m`: Measure function for evaluating clause effectiveness

# Returns
- Vector of merged clauses representing the optimal branching rule

# Algorithm
1. Initialize active clause indices and compute size reductions for each clause
2. Create all possible merging pairs (i,j) where i < j
3. For each pair, check if clauses can be merged (bdistance == 1)
4. If mergeable, compute the merged clause and its size reduction
5. Accept the merge if it improves the overall complexity measure
6. Update active clauses and continue until no more beneficial merges exist
"""
function OptimalBranchingCore.greedymerge(cls::Vector{Vector{Clause{INT}}}, problem::AbstractProblem, bs::AbstractBranchingStatus, variables::Vector, m::AbstractMeasure) where {INT}
    # Initialize active clause indices (all clauses start as active)
    active_set = Set{Int}(1:length(cls))
    cls = copy(cls)  # Create a copy to avoid modifying the original

    # Generate all possible merging pairs (i,j) where i < j to avoid duplicates
    merging_pairs = [(i, j) for i in active_set, j in active_set if i < j]
    n = length(variables)

    # Compute size reduction for each clause (how much it reduces problem complexity)
    # Cache the base measure to avoid repeated computation
    base_measure = measure(bs, m)
    size_reductions = [base_measure - measure(apply_branch(problem, bs, candidate[1], variables), m) for candidate in cls]

    # Compute the complexity base γ from current size reductions
    γ = OptimalBranchingCore.complexity_bv(size_reductions)

    # Main merging loop: continue until no more merging pairs exist
    while !isempty(merging_pairs)
        # Get the next pair to consider for merging (use pop! to avoid O(n) cost)
        i, j = pop!(merging_pairs)

        # Only proceed if both clauses are still active (not already merged)
        if (i in active_set) && (j in active_set)
            # Check all combinations of clauses in groups i and j
            did_merge = false
            ci = cls[i]
            cj = cls[j]
            for ii in 1:length(ci)
                for jj in 1:length(cj)
                    # Check if two clauses can be merged (Hamming distance = 1)
                    if OptimalBranchingCore.bdistance(ci[ii], cj[jj]) == 1
                        # Create the merged clause from the two input clauses
                        cl12 = OptimalBranchingCore.gather2(n, ci[ii], cj[jj])

                        # Skip if the merged clause is invalid (empty mask)
                        if cl12.mask == 0
                            continue
                        end

                        # Compute size reduction for the merged clause
                        l12 = base_measure - measure(apply_branch(problem, bs, cl12, variables), m)

                        # Check if merging improves the complexity measure
                        # The condition: γ^(-size_reductions[i]) + γ^(-size_reductions[j]) >= γ^(-l12) + ε
                        # ensures that the merged clause provides better overall complexity reduction
                        if γ^(-size_reductions[i]) + γ^(-size_reductions[j]) >= γ^(-l12) + 1e-8
                            # Accept the merge: add the merged clause to the clause list
                            push!(cls, [cl12])
                            k = length(cls)  # Index of the new merged clause

                            # Remove the original clauses from active set
                            delete!(active_set, i)
                            delete!(active_set, j)

                            # Add new merging pairs involving the merged clause
                            for ii_act in active_set
                                push!(merging_pairs, (ii_act, k))
                            end

                            # Add the merged clause to active set and update reductions
                            push!(size_reductions, l12)
                            push!(active_set, k)

                            # Recompute complexity base with updated size reductions
                            γ = OptimalBranchingCore.complexity_bv([size_reductions[t] for t in active_set])

                            did_merge = true
                            break
                        end
                    end
                end
                did_merge && break
            end
            did_merge && continue  # Move to next merging pair
        end
    end

    # Return the first clause from each active clause group (sorted for determinism)
    return [cls[k][1] for k in sort!(collect(active_set))]
end

function OptimalBranchingCore.size_reduction(p::AbstractProblem, m::AbstractMeasure, bs::AbstractBranchingStatus, cl::Clause{INT}, variables::Vector) where {INT}
    return measure(bs, m) - measure(apply_branch(p, bs, cl, variables), m)
end
