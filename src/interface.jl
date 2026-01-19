function setup_from_cnf(cnf::CNF)
    return setup_from_sat(Satisfiability(cnf; use_constraints=true))
end

# Use multiple dispatch for different SAT types
function setup_from_sat(sat::ConstraintSatisfactionProblem)
    static = setup_from_csp(sat)
    return TNProblem(static)
end

function solve(
    problem::TNProblem,
    bsconfig::BranchingStrategy,
    reducer::AbstractReducer;
    show_stats::Bool=false,
    target_vars::Vector{Int}=Int[],
    cdcl_cutoff::Float64=1.0
)
    reset_stats!(problem)  # Reset stats before solving
    result = bbsat!(problem, bsconfig, reducer; target_vars, cdcl_cutoff)
    show_stats && print_stats_summary(result.stats)
    return result
end

function solve_sat_problem(
    sat::ConstraintSatisfactionProblem;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MostOccurrenceSelector(3, 6),
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
        selector=MostOccurrenceSelector(1, 2),
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
        assignments = Dict{Symbol,Int}()
        for (i, symbol) in enumerate(sat.symbols)
            assignments[symbol] = get_var_value(result.solution, i)
        end
        return true, assignments, result.stats
    else
        return false, Dict{Symbol,Int}(), result.stats
    end
end

@inline factoring_circuit(n::Int, m::Int, N::Int) = reduceto(CircuitSAT, Factoring(n, m, N)).circuit.circuit
@inline factoring_csp(n::Int, m::Int, N::Int) = CircuitSAT(factoring_circuit(n, m, N); use_constraints=true)
@inline factoring_problem(n::Int, m::Int, N::Int) = setup_from_sat(factoring_csp(n, m, N))

function solve_factoring(
    n::Int, m::Int, N::Int;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        # selector=LookaheadSelector(3, 4, 50),
        # selector=MostOccurrenceSelector(3, 4),
        selector=MinGammaSelector(3, 4, 0),
        measure=NumUnfixedTensors(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer(),
    # reducer::AbstractReducer=GammaOneReducer(10),
    show_stats::Bool=false,
    cdcl_cutoff::Float64=1.0
)
    # Step 1: Create factoring problem and get variable indices
    reduction = reduceto(CircuitSAT, Factoring(n, m, N))
    circuit_sat = CircuitSAT(reduction.circuit.circuit; use_constraints=true)
    q_vars = collect(reduction.q)
    p_vars = collect(reduction.p)
    @info "Factoring setup" n m N symbols = length(circuit_sat.symbols)

    # Step 2: Convert to TN
    tn_problem = setup_from_sat(circuit_sat)
    @info "TN problem" vars = length(tn_problem.static.vars) tensors = length(tn_problem.static.tensors)

    # Step 3: Solve with branch-and-bound (only need to fix p and q variables)
    target_vars = [q_vars; p_vars]
    result = solve(tn_problem, bsconfig, reducer; show_stats, target_vars, cdcl_cutoff)

    !result.found && return nothing, nothing, result.stats
    # Extract solution
    a = bits_to_int(get_var_value(result.solution, q_vars))
    b = bits_to_int(get_var_value(result.solution, p_vars))

    return a, b, result.stats
end

function solve_circuit_sat(
    circuit::Circuit;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MostOccurrenceSelector(3, 2),
        measure=NumUnfixedTensors(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=GammaOneReducer(10),
    show_stats::Bool=false
)
    circuit_sat = CircuitSAT(circuit; use_constraints=true)
    tn_problem = setup_from_sat(circuit_sat)

    result = solve(tn_problem, bsconfig, reducer; show_stats)
    return result.found, result.stats
end
