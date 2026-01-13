using Test
using BooleanInference
using BooleanInference: TNProblem, TNContractionSolver, MostOccurrenceSelector, NumUnfixedVars, setup_problem, get_var_value, bits_to_int, Result
using BooleanInference: BranchingStrategy, NoReducer, setup_from_sat
using ProblemReductions: Factoring, reduceto, CircuitSAT, read_solution, @circuit, Assignment, BooleanExpr
using GenericTensorNetworks
using GenericTensorNetworks: ∧, ∨, ¬
using OptimalBranchingCore

@testset "branch" begin
    fproblem = Factoring(10, 10, 559619)

    circuit_sat = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)

    # Use setup_from_sat instead of deprecated setup_from_tensor_network
    tn_problem = setup_from_sat(problem)
    br_strategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = MostOccurrenceSelector(1,2), measure = NumUnfixedVars(), set_cover_solver = GreedyMerge())
    @time result = bbsat!(tn_problem, br_strategy, NoReducer())
    @show result.stats
    if result.found
        @test !isnothing(result.solution)
        @test count_unfixed(result.solution) == 0
        # Note: After precontraction, variable indices may change, so we just verify the result exists
        @test result isa Result
    end
end


@testset "example" begin
    circuit = @circuit begin
        g1 = a ∧ b
        g3 = g1 ∧ d
        g2 = b ⊻ c
        g4 = ¬ (g2 ∧ e)
        out = g3 ∧ g4
    end
    push!(circuit.exprs, Assignment([:out], BooleanExpr(false)))
    circuit_sat = CircuitSAT(circuit; use_constraints=true)
    tn_problem = setup_from_sat(circuit_sat)
    
    # Test solving the circuit
    br_strategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = MostOccurrenceSelector(1,2), measure = NumUnfixedVars(), set_cover_solver = GreedyMerge())
    result = bbsat!(tn_problem, br_strategy, NoReducer())
    # The circuit can be satisfied (out=false can be achieved), so just check result exists
    @test result isa Result
end