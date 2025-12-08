function setup_from_cnf(cnf::CNF)
    return setup_from_sat(Satisfiability(cnf; use_constraints=true))
end

function setup_from_circuit(cir::Circuit)
    return setup_from_sat(CircuitSAT(cir; use_constraints=true))
end

# Use multiple dispatch for different SAT types
function setup_from_sat(sat::CircuitSAT)
    tn = GenericTensorNetwork(sat)
    t2v = getixsv(tn.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), tn)
    # Merge vec + replace to avoid intermediate allocation
    tensor_data = [replace(vec(t), Tropical(1.0) => zero(Tropical{Float64})) for t in tensors]

    # # Extract circuit metadata and symbols
    # circuit = sat.circuit
    # n_tensors = length(t2v)
    # tensor_symbols = [circuit.exprs[i].expr.head for i in 1:min(n_tensors, length(circuit.exprs))]

    # # Compute circuit topology (depths, fanin, fanout)
    # circuit_info = compute_circuit_info(sat)
    # tensor_info = map_tensor_to_circuit_info(tn, circuit_info, sat)

    # Build BipartiteGraph
    static = setup_problem(length(sat.symbols), t2v, tensor_data)
    TNProblem(static)
end

function setup_from_sat(sat::ConstraintSatisfactionProblem)
    tn = GenericTensorNetwork(sat)
    static = setup_from_tensor_network(tn)
    TNProblem(static)
end

function solve(problem::TNProblem, bsconfig::BranchingStrategy, reducer::AbstractReducer; show_stats::Bool=false)
    reset_problem!(problem)  # Reset stats before solving
    result = bbsat!(problem, bsconfig, reducer)
    show_stats && print_stats_summary(result.stats)
    return result
end

function solve_sat_problem(
    sat::ConstraintSatisfactionProblem;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MinGammaSelector(1,2,TNContractionSolver(), GreedyMerge()),
        measure=NumUnfixedVars(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false
)
    tn_problem = setup_from_sat(sat)
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    return result.found, result.stats
end

function solve_sat_with_assignments(
    sat::ConstraintSatisfactionProblem;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MinGammaSelector(1,2,TNContractionSolver(), GreedyMerge()),
        measure=NumUnfixedVars(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false
)
    # Solve directly to get result
    tn_problem = setup_from_sat(sat)
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)

    if result.found
        # Convert Result to variable assignments
        assignments = Dict{Symbol, Int}()
        for (i, symbol) in enumerate(sat.symbols)
            assignments[symbol] = get_var_value(result.solution, i)
        end
        return true, assignments, result.stats
    else
        return false, Dict{Symbol, Int}(), result.stats
    end
end

@inline factoring_circuit(n::Int, m::Int, N::Int) = reduceto(CircuitSAT, Factoring(n, m, N)).circuit.circuit
@inline factoring_csp(n::Int, m::Int, N::Int) = CircuitSAT(factoring_circuit(n, m, N); use_constraints=true)
@inline factoring_problem(n::Int, m::Int, N::Int) = setup_from_sat(factoring_csp(n, m, N))

function solve_factoring(
    n::Int, m::Int, N::Int;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        # selector=MinGammaSelector(2,4,TNContractionSolver(), GreedyMerge()),
        selector=MostOccurrenceSelector(3,3),
        measure=NumHardTensors(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false
)
    fproblem = Factoring(n, m, N)
    circuit_sat = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)
    tn_problem = setup_from_sat(problem)
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    if !result.found
        return nothing, nothing, result.stats
    end
    a = get_var_value(result.solution, circuit_sat.q)
    b = get_var_value(result.solution, circuit_sat.p)
    return bits_to_int(a), bits_to_int(b), result.stats
end


function solve_circuit_sat(
    circuit::Circuit;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MinGammaSelector(1,2,TNContractionSolver(), GreedyMerge()),
        measure=NumUnfixedVars()
    ),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false
)
    tn_problem = setup_from_circuit(circuit)
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    return result.found, result.stats
end
