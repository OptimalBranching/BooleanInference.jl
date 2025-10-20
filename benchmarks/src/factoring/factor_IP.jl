"""
    findmin(problem::AbstractProblem, optimizer, tag::Bool)

Build and solve a 0-1 integer program corresponding to a CircuitSAT
`problem` using the specified `optimizer` (e.g., `SCIP.Optimizer`).

Details:
- Creates binary variables `x` representing boolean assignments.
- For each circuit constraint, forbids assignments that violate the truth table
  by adding linear inequalities (one per forbidden pattern).
- If the problem provides objectives, aggregates them and either minimizes or
  maximizes depending on `tag` (true => minimize, false => maximize). If no
  objectives exist, uses a dummy objective 0.

Returns a vector of 0/1 integers representing the optimal assignment.
"""
function findmin(problem::AbstractProblem,tag::Bool; optimizer, env)
    # Extract circuit constraints and sizing info
    cons = constraints(problem)
    nsc = ProblemReductions.num_variables(problem)
    maxN = maximum([length(c.variables) for c in cons])
    combs = [ProblemReductions.combinations(2,i) for i in 1:maxN]

    objs = objectives(problem)

    # IP by JuMP
    opt = isnothing(env) ? optimizer() : optimizer(env)
    model = JuMP.direct_model(opt)
    set_silent(model)
    set_string_names_on_creation(model, false)

    # Binary assignment variables for each SAT variable
    JuMP.@variable(model, 0 <= x[i = 1:nsc] <= 1, Int)
    
    # Add constraints that eliminate forbidden patterns in the truth tables.
    for con in cons
        f_vec = findall(!,con.specification)
        num_vars = length(con.variables)
        for f in f_vec
            # Sum of matching literals must be <= num_vars - 1 (i.e., at least one differs)
            JuMP.@constraint(model, sum(j-> iszero(combs[num_vars][f][j]) ? (1 - x[con.variables[j]]) : x[con.variables[j]], 1:num_vars) <= num_vars -1)
        end
    end
    if isempty(objs)
        # No objective: use a constant objective to just find a feasible point
        JuMP.@objective(model, Min, 0)
    else
        # Aggregate objective pieces based on the boolean of the associated variable
        obj_sum = sum(objs) do obj
            (1-x[obj.variables[1]])*obj.specification[1] + x[obj.variables[1]]*obj.specification[2]
        end
        tag ? JuMP.@objective(model,  Min, obj_sum) : JuMP.@objective(model,  Max, obj_sum)
    end

    # Solve and validate feasibility
    JuMP.optimize!(model)
    @assert JuMP.is_solved_and_feasible(model) "The problem is infeasible"
    # Return the 0/1 assignment as integers
    return round.(Int, JuMP.value.(x))
end

"""
    factoring(m, n, N)

Construct a `Factoring(m, n, N)` problem, reduce it to `CircuitSAT`, solve the
resulting IP, and decode the boolean assignment back into integer factors.

Arguments:
- `m`, `n`: bit-widths of the two factors (p and q)
- `N`: the composite integer to factor

Returns a pair `(a, b)` such that `a * b == N` on success.
"""
function factoring(m, n, N; optimizer, env)
    fact3 = Factoring(m, n, N)
    res3 = reduceto(CircuitSAT, fact3)
    # Build CircuitSAT instance with constraints enabled
    problem = CircuitSAT(res3.circuit.circuit; use_constraints=true);
    # Solve for boolean assignments then reconstruct integer factors
    vals = findmin(problem, true; optimizer, env)
    return ProblemReductions.read_solution(fact3, [vals[res3.p]...,vals[res3.q]...])
end