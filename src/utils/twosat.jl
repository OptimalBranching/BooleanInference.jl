# 2-SAT Solver using Strongly Connected Components (Tarjan's algorithm)
# This solver is used when the problem reduces to 2-CNF-SAT (all clauses have at most 2 literals)

"""
    solve_2sat(problem::TNProblem) -> Union{Nothing, Vector{DomainMask}}

Solve a 2-SAT problem using the implication graph and strongly connected components.
Returns a solution (Vector{DomainMask}) if satisfiable, or `nothing` if unsatisfiable.

This solver is applicable when all active tensors have degree ≤ 2.
"""
function solve_2sat(problem::TNProblem)
    n_vars = length(problem.static.vars)
    active_tensors = get_active_tensors(problem.static, problem.doms)

    # Build implication graph: 2n vertices (x_i and ¬x_i for each variable)
    # Vertex 2i-1 represents x_i=true, vertex 2i represents x_i=false
    graph = [Int[] for _ in 1:(2 * n_vars)]

    # Convert each tensor constraint to implications
    for tensor_id in active_tensors
        vars = problem.static.tensors[tensor_id].var_axes
        tensor_obj = problem.static.tensors[tensor_id]

        # Get unfixed variables in this tensor
        unfixed_vars = Int[]
        for var in vars
            if !is_fixed(problem.doms[var])
                push!(unfixed_vars, var)
            end
        end

        # Skip if already handled by propagation
        length(unfixed_vars) > 2 && continue

        if length(unfixed_vars) == 1
            # Unit clause - should have been propagated already, skip
            continue
        elseif length(unfixed_vars) == 2
            # Binary clause: add implications
            var1, var2 = unfixed_vars
            add_binary_implications!(graph, tensor_obj, vars, problem.doms, var1, var2)
        end
    end

    # Find SCCs using Tarjan's algorithm
    sccs = tarjan_scc(graph)

    # Check satisfiability: x_i and ¬x_i must not be in the same SCC
    scc_id = zeros(Int, 2 * n_vars)
    for (id, component) in enumerate(sccs)
        for vertex in component
            scc_id[vertex] = id
        end
    end

    for i in 1:n_vars
        if is_fixed(problem.doms[i])
            continue
        end
        # Check if x_i and ¬x_i are in the same SCC
        if scc_id[2i-1] == scc_id[2i]
            return nothing  # UNSAT
        end
    end

    # Build solution: assign true to variables in later SCCs
    solution = copy(problem.doms)
    for i in 1:n_vars
        if is_fixed(solution[i])
            continue
        end
        # Assign true if ¬x_i appears in an earlier SCC than x_i
        if scc_id[2i] > scc_id[2i-1]
            solution[i] = DM_1
        else
            solution[i] = DM_0
        end
    end

    return solution
end

"""
    add_binary_implications!(graph, tensor, vars, doms, var1, var2)

Add implications to the graph based on a binary constraint.
For a clause (¬a ∨ ¬b), we add: a → ¬b and b → ¬a
For a clause (a ∨ b), we add: ¬a → b and ¬b → a
"""
function add_binary_implications!(graph, tensor, vars, doms, var1, var2)
    # Find positions of var1 and var2 in the tensor
    pos1 = findfirst(==(var1), vars)
    pos2 = findfirst(==(var2), vars)

    # Check which assignments are valid
    # We need to check all 4 combinations of (var1, var2)
    valid_00 = is_valid_assignment(tensor, vars, doms, pos1, false, pos2, false)
    valid_01 = is_valid_assignment(tensor, vars, doms, pos1, false, pos2, true)
    valid_10 = is_valid_assignment(tensor, vars, doms, pos1, true, pos2, false)
    valid_11 = is_valid_assignment(tensor, vars, doms, pos1, true, pos2, true)

    # Add implications based on invalid assignments
    # If (0,0) is invalid: ¬var1 → var1, ¬var2 → var2 (contradiction, should be caught earlier)
    # If (0,1) is invalid: ¬var1 → ¬var2
    # If (1,0) is invalid: var1 → var2
    # If (1,1) is invalid: var1 → ¬var2, var2 → ¬var1

    if !valid_00 && !valid_11 && valid_01 && valid_10
        # XOR constraint: either both true or both false is invalid
        push!(graph[2var1-1], 2var2-1)  # var1 → var2
        push!(graph[2var2-1], 2var1-1)  # var2 → var1
        push!(graph[2var1], 2var2)      # ¬var1 → ¬var2
        push!(graph[2var2], 2var1)      # ¬var2 → ¬var1
    elseif !valid_11
        # At least one must be false: ¬(var1 ∧ var2)
        push!(graph[2var1-1], 2var2)    # var1 → ¬var2
        push!(graph[2var2-1], 2var1)    # var2 → ¬var1
    elseif !valid_00
        # At least one must be true: var1 ∨ var2
        push!(graph[2var1], 2var2-1)    # ¬var1 → var2
        push!(graph[2var2], 2var1-1)    # ¬var2 → var1
    elseif !valid_01
        # If var2 then var1: var2 → var1
        push!(graph[2var2-1], 2var1-1)  # var2 → var1
        push!(graph[2var1], 2var2)      # ¬var1 → ¬var2
    elseif !valid_10
        # If var1 then var2: var1 → var2
        push!(graph[2var1-1], 2var2-1)  # var1 → var2
        push!(graph[2var2], 2var1)      # ¬var2 → ¬var1
    end
end

"""
    is_valid_assignment(tensor, vars, doms, pos1, val1, pos2, val2) -> Bool

Check if assigning var at pos1 to val1 and var at pos2 to val2 is valid for the tensor.
"""
function is_valid_assignment(tensor, vars, doms, pos1, val1, pos2, val2)
    # Build configuration as a bit pattern
    config = 0
    for (i, var) in enumerate(vars)
        bit_value = if is_fixed(doms[var])
            get_var_value(doms, var)
        elseif i == pos1
            val1
        elseif i == pos2
            val2
        else
            # Other unfixed variables - this shouldn't happen for binary constraints
            # Default to 0
            false
        end
        
        if Bool(bit_value)
            config |= (1 << (i - 1))
        end
    end

    # Check if this assignment is satisfiable
    # tensor.tensor[config + 1] != Tropical(0.0) means unsatisfiable
    return tensor.tensor[config + 1] == Tropical(0.0)
end

"""
    tarjan_scc(graph) -> Vector{Vector{Int}}

Compute strongly connected components using Tarjan's algorithm.
Returns components in reverse topological order.
"""
function tarjan_scc(graph)
    n = length(graph)
    index = zeros(Int, n)
    lowlink = zeros(Int, n)
    on_stack = falses(n)
    stack = Int[]
    current_index = 1
    sccs = Vector{Int}[]

    function strongconnect(v)
        index[v] = current_index
        lowlink[v] = current_index
        current_index += 1
        push!(stack, v)
        on_stack[v] = true

        for w in graph[v]
            if index[w] == 0
                strongconnect(w)
                lowlink[v] = min(lowlink[v], lowlink[w])
            elseif on_stack[w]
                lowlink[v] = min(lowlink[v], index[w])
            end
        end

        if lowlink[v] == index[v]
            scc = Int[]
            while true
                w = pop!(stack)
                on_stack[w] = false
                push!(scc, w)
                w == v && break
            end
            push!(sccs, scc)
        end
    end

    for v in 1:n
        if index[v] == 0
            strongconnect(v)
        end
    end

    return sccs
end

"""
    is_2sat_reducible(problem::TNProblem) -> Bool

Check if the problem has reduced to 2-SAT (all active tensors have degree ≤ 2).
"""
function is_2sat_reducible(problem::TNProblem)
    active_tensors = get_active_tensors(problem.static, problem.doms)
    for tensor_id in active_tensors
        vars = problem.static.tensors[tensor_id].var_axes
        degree = 0
        for var in vars
            !is_fixed(problem.doms[var]) && (degree += 1)
        end
        degree > 2 && return false
    end
    return true
end
