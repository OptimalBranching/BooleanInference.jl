function setup_from_cnf(cnf::CNF)
    return setup_from_sat(Satisfiability(cnf; use_constraints=true))
end

function setup_from_circuit(cir::Circuit)
    return setup_from_sat(CircuitSAT(cir; use_constraints=true))
end

function setup_from_sat(sat::ConstraintSatisfactionProblem)
    tn = GenericTensorNetwork(sat)
    static = setup_from_tensor_network(tn)
    TNProblem(static)
end

function solve(problem::TNProblem, bsconfig::BranchingStrategy, reducer::AbstractReducer)
    depth = branch_and_reduce(problem, bsconfig, reducer, Tropical{Float64}; show_progress=false)
    res = last_branch_problem(problem)
    return (res, depth)
end

function solve_sat_problem(
    sat::ConstraintSatisfactionProblem; 
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(), 
        selector=LeastOccurrenceSelector(1, 2), 
        measure=NumUnfixedVars()
    ), 
    reducer::AbstractReducer=NoReducer()
)
    tn_problem = setup_from_sat(sat)
    result, depth = solve(tn_problem, bsconfig, reducer)
    satisfiable = !isnothing(result)
    return satisfiable, result, depth
end

function solve_sat_with_assignments(
    sat::ConstraintSatisfactionProblem;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(), 
        selector=LeastOccurrenceSelector(1, 2), 
        measure=NumUnfixedVars()
    ), 
    reducer::AbstractReducer=NoReducer()
)
    satisfiable, result, depth = solve_sat_problem(sat; bsconfig, reducer)
    if satisfiable && !isnothing(result)
        # Convert TNProblem result to variable assignments
        assignments = Dict{Symbol, Int}()
        for (i, symbol) in enumerate(sat.symbols)
            assignments[symbol] = get_var_value(result, i)
        end
        return satisfiable, assignments, depth
    else
        return false, Dict{Symbol, Int}(), depth
    end
end

function solve_factoring(
    n::Int, m::Int, N::Int;
    bsconfig::BranchingStrategy=BranchingStrategy(table_solver=TNContractionSolver(), selector=LeastOccurrenceSelector(1, 2), measure=NumUnfixedVars()), 
    reducer::AbstractReducer=NoReducer()
)
    fproblem = Factoring(n, m, N)
    circuit_sat = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)
    tn_problem = setup_from_sat(problem)
    res, _ = solve(tn_problem, bsconfig, reducer)
    isnothing(res) && return nothing, nothing
    a = get_var_value(res, circuit_sat.q)
    b = get_var_value(res, circuit_sat.p)
    return bits_to_int(a), bits_to_int(b)
end
