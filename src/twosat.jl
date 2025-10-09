# 2-SAT helper: implication graph utilities
function _lit_index(v::Int, is_pos::Bool)
    return 2 * v + (is_pos ? 0 : 1)
end

function _add_implication!(g::Vector{Vector{Int}}, gr::Vector{Vector{Int}}, u::Int, v::Int)
    push!(g[u], v)
    push!(gr[v], u)
end

# Build 2-CNF from edges with ≤2 undecided vars and solve by SCC. If satisfiable, apply solution.
function _try_2sat(problem::BooleanInferenceProblem, bs::AbstractBranchingStatus, measure::AbstractMeasure, stats::SearchStatistics)
    # Only proceed if every active edge has ≤ 2 undecided variables
    for cnt in bs.undecided_literals
        if cnt > 2
            return BranchResult(false, bs)
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
            return BranchResult(false, bs)  # unsat under 2-SAT abstraction
        end
        assign[v] = (comp[t] > comp[f]) ? 1 : 0
    end

    # Apply assignments only to undecided variables, with deduction
    bs_new = bs
    for v in 1:n
        if readbit(bs_new.decided_mask, v) == 0
            bit = assign[v]
            bs_new = apply_branch(problem, bs_new, Clause(1, bit), [v])
        end
    end
    # Track successful 2-SAT application
    increment_two_sat!(stats)
    
    # Final consistency check
    stopped, res = check_stopped(bs_new, measure, stats)
    if stopped && res
        return BranchResult(true, bs_new)
    else
        return BranchResult(false, bs)
    end
end

function num_of_2sat_clauses(bs::AbstractBranchingStatus)
    return count(x -> x == 2, bs.undecided_literals)
end


