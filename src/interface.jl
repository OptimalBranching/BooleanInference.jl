# Performance Note:
# For maximum performance on large problems, set verbose=false and show_stats=false.
# This disables all detailed statistics collection (timing, path tracking, etc.)
# and only collects basic counters.

function setup_from_cnf(cnf::CNF; verbose::Bool = false)
    return setup_from_sat(Satisfiability(cnf; use_constraints=true); verbose=verbose)
end

function setup_from_circuit(cir::Circuit; verbose::Bool = false)
    return setup_from_sat(CircuitSAT(cir; use_constraints=true); verbose=verbose)
end

function setup_from_sat(sat::ConstraintSatisfactionProblem; verbose::Bool = false)
    tn = GenericTensorNetwork(sat)
    static = setup_from_tensor_network(tn)
    TNProblem(static; verbose=verbose)
end

function solve(problem::TNProblem, bsconfig::BranchingStrategy, reducer::AbstractReducer; show_stats::Bool=false)
    reset_branching_stats!(problem)  # Reset stats before solving
    depth = OptimalBranchingCore.branch_and_reduce(problem, bsconfig, reducer, Tropical{Float64}; show_progress=false)
    res = last_branch_problem(problem)
    stats = get_branching_stats(problem)
    clear_all_region_caches!()
    if show_stats
        print_stats_summary(stats)
    end
    return (res, depth, stats)
end

function solve_sat_problem(
    sat::ConstraintSatisfactionProblem; 
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(1,2), 
        selector=MostOccurrenceSelector(), 
        measure=NumUnfixedVars()
    ), 
    reducer::AbstractReducer=NoReducer(),
    verbose::Bool = false,
    show_stats::Bool=false
)
    tn_problem = setup_from_sat(sat; verbose=verbose)
    result, depth, stats = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    satisfiable = !isnothing(result)
    return satisfiable, stats
end

function solve_sat_with_assignments(
    sat::ConstraintSatisfactionProblem; 
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(1,2), 
        selector=MostOccurrenceSelector(), 
        measure=NumUnfixedVars()
    ), 
    reducer::AbstractReducer=NoReducer(),
    verbose::Bool = false,
    show_stats::Bool=false
)
    # Solve directly to get result
    tn_problem = setup_from_sat(sat; verbose=verbose)
    result, depth, stats = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    satisfiable = !isnothing(result)
    
    if satisfiable && !isnothing(result)
        # Convert TNProblem result to variable assignments
        assignments = Dict{Symbol, Int}()
        for (i, symbol) in enumerate(sat.symbols)
            assignments[symbol] = get_var_value(result, i)
        end
        return satisfiable, assignments, stats
    else
        return false, Dict{Symbol, Int}(), stats
    end
end

function solve_factoring(
    n::Int, m::Int, N::Int;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(1,2),
        # selector=MinGammaSelector(TNContractionSolver(1,2), GreedyMerge()),
        selector=MostOccurrenceSelector(),
        measure=NumUnfixedVars(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer(),
    verbose::Bool=false, show_stats::Bool=false
)
    fproblem = Factoring(n, m, N)
    circuit_sat = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)
    # @show circuit_sat.circuit.circuit
    # distances = circuit_output_distances(circuit_sat.circuit.circuit)
    # @show distances
    tn_problem = setup_from_sat(problem; verbose=verbose)
    @show tn_problem
    if verbose
        unique_tensors = length(tn_problem.static.precomputed_masks)
        total_tensors = length(tn_problem.static.tensors)
        println("Unique tensor types: $unique_tensors (out of $total_tensors total)")
    end
    res, depth, stats = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    isnothing(res) && return nothing, nothing, stats
    a = get_var_value(res, circuit_sat.q)
    b = get_var_value(res, circuit_sat.p)
    return bits_to_int(a), bits_to_int(b), stats
end


function solve_circuit_sat(
    circuit::Circuit;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(1,2),
        selector=MostOccurrenceSelector(),
        measure=NumUnfixedVars()
    ),
    reducer::AbstractReducer=NoReducer(),
    verbose::Bool=false,
    show_stats::Bool=false
)
    tn_problem = setup_from_circuit(circuit; verbose)
    res, depth, stats = solve(tn_problem, bsconfig, reducer; show_stats=show_stats)
    satisfiable = !isnothing(res)
    return satisfiable, stats
end
