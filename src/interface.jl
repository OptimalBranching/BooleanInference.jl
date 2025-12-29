function setup_from_cnf(cnf::CNF)
    return setup_from_sat(Satisfiability(cnf; use_constraints=true))
end

function setup_from_circuit(cir::Circuit)
    return setup_from_sat(CircuitSAT(cir; use_constraints=true))
end

# Use multiple dispatch for different SAT types
function setup_from_sat(sat::ConstraintSatisfactionProblem; learned_clauses::Vector{ClauseTensor}=ClauseTensor[], precontract::Bool=false, protected_vars::Vector{Int}=Int[])
    # Direct conversion from CSP to BipartiteGraph, avoiding GenericTensorNetwork overhead
    static = setup_from_csp(sat; precontract, protected_vars)
    return TNProblem(static; learned_clauses)
end

function solve(problem::TNProblem, bsconfig::BranchingStrategy, reducer::AbstractReducer; show_stats::Bool=false, logger::AbstractLogger=NoLogger())
    reset_stats!(problem)  # Reset stats before solving
    result = bbsat!(problem, bsconfig, reducer; logger=logger)
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
    show_stats::Bool=false,
    logger::AbstractLogger=NoLogger()
)
    tn_problem = setup_from_sat(sat)
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats, logger=logger)
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
    show_stats::Bool=false,
    logger::AbstractLogger=NoLogger()
)
    # Solve directly to get result
    tn_problem = setup_from_sat(sat)
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats, logger=logger)

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
        selector=MinGammaSelector(3, 2),
        # selector=MostOccurrenceSelector(3,3),
        measure=NumUnfixedTensors(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false,
    logger::AbstractLogger=NoLogger(),
)
    # Step 1: Create factoring problem and get variable indices
    reduction = reduceto(CircuitSAT, Factoring(n, m, N))
    # Rebuild with use_constraints=true to get LocalConstraints for TN conversion
    circuit_sat = CircuitSAT(reduction.circuit.circuit; use_constraints=true)
    q_indices = collect(reduction.q)
    p_indices = collect(reduction.p)

    # The variables we care about - these should not be eliminated during precontraction
    protected = [q_indices; p_indices]

    @info "Factoring setup" n m N symbols = length(circuit_sat.symbols)

    # Step 2: Convert to TN WITH precontraction
    tn_problem = setup_from_sat(circuit_sat; precontract=false, protected_vars=protected)

    # Map original indices to compressed variable space
    orig_to_new = tn_problem.static.orig_to_new
    q_vars = [orig_to_new[i] for i in q_indices]
    p_vars = [orig_to_new[i] for i in p_indices]

    # Verify all protected variables are still in the network
    @assert all(v -> v > 0, q_vars) "Some q variables were unexpectedly eliminated"
    @assert all(v -> v > 0, p_vars) "Some p variables were unexpectedly eliminated"

    @info "After TN precontraction" tn_vars = length(tn_problem.static.vars) tn_tensors = length(tn_problem.static.tensors)

    # # Step 3: Optionally use CDCL to learn clauses from the precontracted TN
    # learned_tensors = ClauseTensor[]
    # if use_cdcl
    #     # Convert precontracted TN to CNF
    #     cnf = tn_to_cnf(tn_problem.static)
    #     nvars = num_tn_vars(tn_problem.static)

    #     @info "CDCL clause mining" cnf_clauses = length(cnf) nvars = nvars

    #     # Try CDCL solver with clause learning
    #     status, model, learned = solve_and_mine(cnf; nvars=nvars, conflict_limit=conflict_limit, max_len=max_clause_len)
    #     if status == :sat
    #         # CDCL solved it directly!
    #         a = bits_to_int([model[v] > 0 for v in q_vars])
    #         b = bits_to_int([model[v] > 0 for v in p_vars])
    #         @info "Solved by CDCL" a b
    #         return a, b, BranchingStats()
    #     elseif status == :unsat
    #         error("Problem is UNSAT")
    #     else
    #         # Timeout - use learned clauses
    #         learned_tensors = ClauseTensor.(learned)
    #         @info "CDCL timeout, learned $(length(learned_tensors)) clauses"
    #     end
    # end
    # # Step 4: Add learned clauses to the problem
    # if !isempty(learned_tensors)
    #     # Rebuild problem with learned clauses (already in compressed variable space)
    #     tn_problem = TNProblem(tn_problem.static; learned_clauses=learned_tensors)
    # end

    # Step 5: Solve with branch-and-bound
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats, logger=logger)

    if !result.found
        return nothing, nothing, result.stats
    end

    # Extract solution
    a = bits_to_int(get_var_value(result.solution, q_vars))
    b = bits_to_int(get_var_value(result.solution, p_vars))

    return a, b, result.stats
end

function solve_circuit_sat(
    circuit::Circuit;
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MostOccurrenceSelector(3, 1),
        measure=NumUnfixedVars(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false,
    logger::AbstractLogger=NoLogger(),
    use_cdcl::Bool=false,
    conflict_limit::Int=40000,
    max_clause_len::Int=5
)
    circuit_sat = CircuitSAT(circuit; use_constraints=true)

    # Step 1: Convert to TN
    tn_problem = setup_from_sat(circuit_sat; precontract=false, protected_vars=Int[])

    # Step 2: Optionally use CDCL to learn clauses
    learned_tensors = ClauseTensor[]
    if use_cdcl
        # Convert TN to CNF
        cnf = tn_to_cnf(tn_problem.static)
        nvars = num_tn_vars(tn_problem.static)

        @info "CDCL clause mining" cnf_clauses = length(cnf) nvars = nvars

        # Try CDCL solver with clause learning
        status, model, learned = solve_and_mine(cnf; nvars=nvars, conflict_limit=conflict_limit, max_len=max_clause_len)
        if status == :sat
            # CDCL solved it directly!
            @info "Solved by CDCL"
            return true, BranchingStats()
        elseif status == :unsat
            @info "UNSAT detected by CDCL"
            return false, BranchingStats()
        else
            # Timeout - use learned clauses
            learned_tensors = ClauseTensor.(learned)
            @info "CDCL timeout, learned $(length(learned_tensors)) clauses"
        end
    end

    # Step 3: Add learned clauses to the problem if any
    if !isempty(learned_tensors)
        # Rebuild problem with learned clauses (already in compressed variable space)
        tn_problem = TNProblem(tn_problem.static; learned_clauses=learned_tensors)
    end

    # Step 4: Solve with branch-and-bound
    result = solve(tn_problem, bsconfig, reducer; show_stats=show_stats, logger=logger)
    @show result.solution
    return result.found, result.stats
end
