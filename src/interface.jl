function convert_cnf_to_bip(cnf::CNF)
    return convert_sat_to_bip(Satisfiability(cnf; use_constraints=true))
end

function convert_sat_to_bip(sat::ConstraintSatisfactionProblem)
    problem = GenericTensorNetwork(sat)
    # Get labels of all tensors in the circuit
    he2v = getixsv(problem.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), problem)
    vec_tensors = [vec(t) for t in tensors]
    new_tensors = [replace(t, Tropical(1.0) => zero(Tropical{Float64})) for t in vec_tensors]
    return BooleanInferenceProblem(new_tensors, he2v, length(problem.problem.symbols)), problem.problem.symbols
end

function convert_circuit_to_bip(cir::Circuit)
    return convert_sat_to_bip(CircuitSAT(cir; use_constraints=true))
end

function solve_sat_problem(sat::ConstraintSatisfactionProblem; bsconfig::BranchingStrategy=BranchingStrategy(table_solver=TNContractionSolver(), selector=KNeighborSelector(1,1), measure=NumOfVertices()), reducer=NoReducer())
    p, syms = convert_sat_to_bip(sat)
    satisfiable, assignment, stats = solve_boolean_inference_problem(p; bsconfig, reducer)
    return satisfiable, assignment, stats
end

"""
    solve_factoring(n::Int, m::Int, N::Int; bsconfig, reducer)

Solve an integer factoring instance.

Returns `(a, b, stats)` where `a * b = N`.
"""
function solve_factoring(n::Int, m::Int, N::Int; bsconfig::BranchingStrategy=BranchingStrategy(table_solver=TNContractionSolver(), selector=KNeighborSelector(2,1), measure=WeightedClauseArityMeasure()), reducer=NoReducer())
    fproblem = Factoring(m, n, N)
    res = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(res.circuit.circuit; use_constraints=true)
    ans, vals, stats = solve_sat_problem(problem; bsconfig, reducer)
    a, b = ProblemReductions.read_solution(fproblem, [vals[res.p]..., vals[res.q]...])
    # println("factoring result: $a × $b = $N")
    # println(stats)
    return a, b, stats
end

function solve_sat_with_assignments(sat::ConstraintSatisfactionProblem)
    satisfiable, assignment, stats = solve_sat_problem(sat)
    return satisfiable, Dict(zip(sat.symbols, assignment)), stats
end

"""
    solve_boolean_inference_problem(bip::BooleanInferenceProblem; bsconfig, reducer)

Solve a Boolean inference problem.

Returns `(satisfiable::Bool, assignment::Vector{Int}, stats::SearchStatistics)`.
"""
function solve_boolean_inference_problem(bip::BooleanInferenceProblem; bsconfig::BranchingStrategy=BranchingStrategy(table_solver=TNContractionSolver(), selector=KNeighborSelector(2,1), measure=NumOfVertices()), reducer=NoReducer())
    # Initialize branching status and statistics
    bs = initialize_branching_status(bip)
    bs = deduction_reduce(bip, bs, collect(1:length(bip.he2v)))
    stats = SearchStatistics()
    @dbg DEBUG_BASIC 0 "INIT" "$(bip.literal_num) variables -> $(count_ones(bs.decided_mask)) decided"
    # Start search
    result = branch_and_reduce(bip, bs, bsconfig, reducer; stats=stats)
    assignment = get_answer(result.status, bip.literal_num)
    
    return result.success, assignment, stats
end