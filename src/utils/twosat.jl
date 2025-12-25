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
        @assert length(unfixed_vars) <= 2 "Tensor $(tensor_id) has more than 2 unfixed variables"

        if length(unfixed_vars) == 1
            # Unit clause - should have been propagated already, skip
            continue
        elseif length(unfixed_vars) == 2
            # Binary clause: add implications
            var1, var2 = unfixed_vars
            add_binary_implications!(problem.static, graph, tensor_obj, vars, problem.doms, var1, var2)
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

    # Build solution: assign true to the literal that appears later in the
    # reverse-topological SCC order (Tarjan yields reverse topo order).
    solution = copy(problem.doms)
    for i in 1:n_vars
        if is_fixed(solution[i])
            continue
        end
        # Standard 2-SAT assignment rule with Tarjan's reverse topological order:
        # assign x = true if comp(x) appears earlier in the Tarjan list
        # (i.e., lower index) than comp(¬x); otherwise x = false.
        if scc_id[2i-1] < scc_id[2i]
            solution[i] = DM_1
        else
            solution[i] = DM_0
        end
    end

    return solution
end

"""
    add_binary_implications!(static, graph, tensor, vars, doms, var1, var2)

Add implications to the graph based on a binary constraint by checking forbidden assignments.
Uses the standard 2-SAT reduction: a forbidden assignment (val1, val2) implies clauses
(¬(var1=val1) ∨ ¬(var2=val2)).
"""
function add_binary_implications!(static, graph, tensor, vars, doms, var1, var2)
    # Find positions of var1 and var2 in the tensor
    pos1 = findfirst(==(var1), vars)
    pos2 = findfirst(==(var2), vars)
    
    # Check all 4 combinations
    valid_00 = is_valid_assignment(static, tensor, vars, doms, pos1, false, pos2, false)
    valid_01 = is_valid_assignment(static, tensor, vars, doms, pos1, false, pos2, true)
    valid_10 = is_valid_assignment(static, tensor, vars, doms, pos1, true, pos2, false)
    valid_11 = is_valid_assignment(static, tensor, vars, doms, pos1, true, pos2, true)

    # Vertex indices in the graph:
    # 2k-1 represents x_k = true
    # 2k   represents x_k = false
    
    u_true  = 2var1 - 1
    u_false = 2var1
    v_true  = 2var2 - 1
    v_false = 2var2

    # Case 1: (0, 0) is invalid => (A or B) => (!A -> B), (!B -> A)
    if !valid_00
        push!(graph[u_false], v_true)
        push!(graph[v_false], u_true)
    end

    # Case 2: (0, 1) is invalid => (A or !B) => (!A -> !B), (B -> A)
    if !valid_01
        push!(graph[u_false], v_false)
        push!(graph[v_true], u_true)
    end

    # Case 3: (1, 0) is invalid => (!A or B) => (A -> B), (!B -> !A)
    if !valid_10
        push!(graph[u_true], v_true)
        push!(graph[v_false], u_false)
    end

    # Case 4: (1, 1) is invalid => (!A or !B) => (A -> !B), (B -> !A)
    if !valid_11
        push!(graph[u_true], v_false)
        push!(graph[v_true], u_false)
    end
end

"""
    is_valid_assignment(static, tensor, vars, doms, pos1, val1, pos2, val2) -> Bool

Check if assigning var at pos1 to val1 and var at pos2 to val2 is valid for the tensor.
"""
function is_valid_assignment(static, tensor, vars, doms, pos1, val1, pos2, val2)
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
    # dense_tensor[config + 1] == true means satisfiable (equivalent to one(Tropical{Float64}))
    dense_tensor = get_dense_tensor(static, tensor)
    return dense_tensor[config + 1]
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
