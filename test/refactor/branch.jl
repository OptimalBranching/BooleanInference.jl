using Test
using BooleanInference
using BooleanInference: TNProblem, TNContractionSolver, LeastOccurrenceSelector, NumUnfixedVars, setup_from_tensor_network, setup_problem, select_variables, get_cached_region
using BooleanInference: BranchingStrategy, NoReducer
using OptimalBranchingCore: branching_table, branch_and_reduce
using ProblemReductions: Factoring, reduceto, CircuitSAT
using GenericTensorNetworks

function generate_example_problem(n::Int = 12)
    fproblem = Factoring(n, n, 10395529)
    res = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(res.circuit.circuit; use_constraints=true)
    return problem
end

@testset "branch" begin
    problem = generate_example_problem(2)
    tn = GenericTensorNetwork(problem)
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
    br_strategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = LeastOccurrenceSelector(2, 5), measure = NumUnfixedVars())
    result = branch_and_reduce(tn_problem, br_strategy, NoReducer(), Tropical{Float64}; show_progress=true)
    @show result
end