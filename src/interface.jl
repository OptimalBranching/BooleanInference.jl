function setup_from_cnf(cnf::CNF)
    return setup_from_sat(Satisfiability(cnf; use_constraints=true))
end

function setup_from_circuit(cir::Circuit)
    return setup_from_sat(CircuitSAT(cir; use_constraints=true))
end

# Use multiple dispatch for different SAT types
function setup_from_sat(sat::ConstraintSatisfactionProblem; learned_clauses::Vector{ClauseTensor}=ClauseTensor[], precontract::Bool=false)
    # Direct conversion from CSP to BipartiteGraph, avoiding GenericTensorNetwork overhead
    static = setup_from_csp(sat; precontract)
    return TNProblem(static; learned_clauses)
end

function solve(problem::TNProblem, bsconfig::BranchingStrategy, reducer::AbstractReducer; show_stats::Bool=false)
    reset_stats!(problem)  # Reset stats before solving
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
        selector=MostOccurrenceSelector(3,9),
        measure=NumUnfixedTensors(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false
)
    function _solve_and_mine_factoring(reduction; conflict_limit::Int, max_len::Int)
        cnf, _ = circuit_to_cnf(reduction.circuit.circuit)
        status, model, learned = solve_and_mine(cnf; conflict_limit, max_len)
        a = [model[i] > 0 for i in reduction.q]
        b = [model[i] > 0 for i in reduction.p]
        learned_tensors = ClauseTensor.(learned)
        return status, bits_to_int(a), bits_to_int(b), learned_tensors
    end

    circuit_sat = reduceto(CircuitSAT, Factoring(n, m, N))
    status, a, b, learned_tensors = _solve_and_mine_factoring(circuit_sat; conflict_limit=30000, max_len=5)
    status == :sat && return a, b, BranchingStats()
    @assert status != :unsat

    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)
    tn_problem = setup_from_sat(problem; learned_clauses=learned_tensors, precontract=false)

    # tn_problem = setup_from_sat(problem)
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    !result.found && return nothing, nothing, result.stats
    
    q_vars = map_vars_checked(tn_problem, circuit_sat.q, "q")
    p_vars = map_vars_checked(tn_problem, circuit_sat.p, "p")
    a = get_var_value(result.solution, q_vars)
    b = get_var_value(result.solution, p_vars)
    return bits_to_int(a), bits_to_int(b), result.stats
end

function solve_circuit_sat(
    circuit::Circuit;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MinGammaSelector(1,2,TNContractionSolver(),GreedyMerge()),
        measure=NumUnfixedVars()
    ),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false
)
    tn_problem = setup_from_circuit(circuit)
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    return result.found, result.stats
end
