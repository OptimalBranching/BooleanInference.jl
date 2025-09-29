function OptimalBranchingCore.apply_branch(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, clause::Clause{INT}, vertices::Vector{T}) where {INT<:Integer,T<:Integer}
    bs_new, aedges = decide_literal(bs, p, vertices, clause)
    return deduction_reduce(p, bs_new, aedges)
end

# 2-SAT helper: implication graph utilities
function _lit_index(v::Int, is_pos::Bool)
    return 2 * v + (is_pos ? 0 : 1)
end

function _add_implication!(g::Vector{Vector{Int}}, gr::Vector{Vector{Int}}, u::Int, v::Int)
    push!(g[u], v)
    push!(gr[v], u)
end

# Build 2-CNF from edges with ≤2 undecided vars and solve by SCC. If satisfiable, apply solution.
function _try_2sat(problem::BooleanInferenceProblem, bs::AbstractBranchingStatus)
    # Only proceed if every active edge has ≤ 2 undecided variables
    for cnt in bs.undecided_literals
        if cnt > 2
            return false, bs, 0
        end
    end

    n = problem.literal_num
    g = [Int[] for _ in 1:(2 * n + 2)]
    gr = [Int[] for _ in 1:(2 * n + 2)]

    # Add unit clauses for decided variables: x = val
    for v in 1:n
        if readbit(bs.decided_mask, v) == 1
            val = Int(readbit(bs.config, v))
            lit_pos = (val == 1)
            a = _lit_index(v, lit_pos)
            na = a ⊻ 1
            _add_implication!(g, gr, na, a)
        end
    end

    # For each edge, forbid disallowed tuples of undecided variables
    for (edge_idx, cnt) in enumerate(bs.undecided_literals)
        cnt <= 0 && continue  # satisfied (-1) or checked as unsat (0) earlier

        he = problem.he2v[edge_idx]
        # Compute base index from decided vars
        base = 0
        undecided_vs = Int[]
        undecided_pos = Int[]
        for j in 1:length(he)
            v = he[j]
            if readbit(bs.decided_mask, v) == 1
                base += Int(readbit(bs.config, v)) * (1 << (j - 1))
            else
                push!(undecided_vs, v)
                push!(undecided_pos, j)
            end
        end

        m = length(undecided_vs)
        # Enumerate all assignments to undecided variables and forbid infeasible ones
        for assign in 0:(1 << m) - 1
            sum1 = base
            # Build tuple and compute index
            local_idx = 0
            for k in 1:m
                local_idx += 1
                bitk = Int(readbit(assign, local_idx))
                sum1 += bitk * (1 << (undecided_pos[k] - 1))
            end
            feasible = (problem.tensors[edge_idx][sum1 + 1] == Tropical(0.0))
            if !feasible
                if m == 1
                    v = undecided_vs[1]
                    b = Int(readbit(assign, 1))
                    # Clause: (v != b)
                    lit_pos = (b == 0)  # v != 0  => v; v != 1 => ¬v
                    a = _lit_index(v, lit_pos)
                    na = a ⊻ 1
                    _add_implication!(g, gr, na, a)
                elseif m == 2
                    v1 = undecided_vs[1]; v2 = undecided_vs[2]
                    b1 = Int(readbit(assign, 1)); b2 = Int(readbit(assign, 2))
                    # Clause: (v1 != b1) ∨ (v2 != b2)
                    a = _lit_index(v1, b1 == 0)
                    b = _lit_index(v2, b2 == 0)
                    na = a ⊻ 1; nb = b ⊻ 1
                    _add_implication!(g, gr, na, b)
                    _add_implication!(g, gr, nb, a)
                end
            end
        end
    end

    # Kosaraju SCC
    visited = falses(2 * n + 2)
    order = Int[]
    function dfs1(u)
        visited[u] && return
        visited[u] = true
        for v in g[u]
            dfs1(v)
        end
        push!(order, u)
    end
    for u in 1:(2 * n + 2)
        dfs1(u)
    end

    comp = fill(0, 2 * n + 2)
    cid = 0
    function dfs2(u)
        comp[u] = cid
        for v in gr[u]
            if comp[v] == 0
                dfs2(v)
            end
        end
    end
    for u in Iterators.reverse(order)
        if comp[u] == 0
            cid += 1
            dfs2(u)
        end
    end

    # Check consistency and extract assignment
    assign = Vector{Int}(undef, n)
    for v in 1:n
        t = _lit_index(v, true)
        f = t ⊻ 1
        if comp[t] == comp[f]
            return false, bs, 1  # unsat under 2-SAT abstraction
        end
        assign[v] = (comp[t] > comp[f]) ? 1 : 0
    end

    # Apply assignments only to undecided variables, with deduction
    bs_new = bs
    for v in 1:n
        if readbit(bs_new.decided_mask, v) == 0
            bit = assign[v]
            bs_new = OptimalBranchingCore.apply_branch(problem, bs_new, Clause(1, bit), [v])
        end
    end
    # Final consistency check
    stopped, res, _ = check_stopped(bs_new)
    if stopped && res
        return true, bs_new, 1
    else
        return false, bs, 1
    end
end

# Try to finish by enumerating assignments for up to 2 undecided variables
function _finish_with_up_to_two(problem::BooleanInferenceProblem, bs::AbstractBranchingStatus)
    undecided_vars = [i for i in 1:problem.literal_num if readbit(bs.decided_mask, i) == 0]
    n = length(undecided_vars)
    if n == 0
        return true, bs, 1
    end
    n > 2 && return false, bs, 0
    mask = (Int(1) << n) - 1
    for val in 0:(1 << n) - 1
        bs_try = OptimalBranchingCore.apply_branch(problem, bs, Clause(mask, val), undecided_vars)
        stopped, res, _ = check_stopped(bs_try)
        if stopped && res
            return true, bs_try, 1
        end
    end
    return false, bs, 1
end

function OptimalBranchingCore.branch_and_reduce(problem::BooleanInferenceProblem, bs::AbstractBranchingStatus, config::BranchingStrategy, reducer::AbstractReducer; depth::Int=0)
    # Determines if search should terminate
    stopped, res, count_num = check_stopped(bs)
    stopped && return res, bs, count_num

    # If there are at most two undecided variables globally, finish by enumeration (equivalent to reducing to 2-SAT)
    done2, bs2, cnt2 = _finish_with_up_to_two(problem, bs)
    if cnt2 > 0
        count_num += cnt2
    end
    done2 && return true, bs2, count_num

    # If every active edge has ≤ 2 undecided variables, reduce to 2-SAT and solve
    done2sat, bs2sat, cnt2sat = _try_2sat(problem, bs)
    if cnt2sat > 0
        count_num += cnt2sat
    end
    done2sat && return true, bs2sat, count_num

    # branch the problem
    # select a subset of variables
    subbip = select_variables(problem, bs, config.measure, config.selector)
    # compute the BranchingTable
    tbl = branching_table(problem, bs, config.table_solver, subbip)
    iszero(tbl.bit_length) && return false, bs, 1

    result = optimal_branching_rule(tbl, subbip.vs, bs, problem, config.measure, config.set_cover_solver)  # compute the optimal branching rule
    for branch in OptimalBranchingCore.get_clauses(result)
        res, bs_new, count_num1 = branch_and_reduce(problem, apply_branch(problem, bs, branch, subbip.vs), config, reducer; depth=depth+1)
        count_num += count_num1
        if res
            return res, bs_new, count_num
        end
    end
    return false, bs, count_num
end

function check_stopped(bs::AbstractBranchingStatus)
    # global BRANCHNUMBER
    # if there is no clause, then the problem is solved.
    if all(bs.undecided_literals .== -1)
        # BRANCHNUMBER += 1
        return true, true, 1
    end
    if any(bs.undecided_literals .== 0)
        # BRANCHNUMBER += 1
        return true, false, 1
    end
    return false, false, 0
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
