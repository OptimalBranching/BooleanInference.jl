using Test
using BooleanInference
using BooleanInference: TNProblem, TNContractionSolver, MostOccurrenceSelector, NumUnfixedVars, setup_from_tensor_network, setup_problem, select_variables, get_var_value, bits_to_int, branch_and_reduce!, Result
using BooleanInference: BranchingStrategy, NoReducer
using ProblemReductions: Factoring, reduceto, CircuitSAT, read_solution
using GenericTensorNetworks
# using Logging

# ENV["JULIA_DEBUG"] = "BooleanInference"

@testset "branch" begin
    fproblem = Factoring(10, 10, 559619)

    circuit_sat = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)

    tn = GenericTensorNetwork(problem)
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
    br_strategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = MostOccurrenceSelector(1,2), measure = NumUnfixedVars())
    @time result = branch_and_reduce!(tn_problem, br_strategy, NoReducer(), Result; show_progress=false)
    @show result.stats
    if result.found
        @test !isnothing(result.solution)
        @test count_unfixed(result.solution) == 0
        a = get_var_value(result.solution, circuit_sat.q)
        b = get_var_value(result.solution, circuit_sat.p)
        @test bits_to_int(a) * bits_to_int(b) == 559619
    end
end
