using Test
using BooleanInference
using BooleanInference: TNProblem, NumUnfixedVars, setup_problem
using OptimalBranchingCore
using TropicalNumbers: Tropical
using GenericTensorNetworks: ∧, ∨, ¬, @bools, Satisfiability

# Helper function to create a simple test problem using new API (BitVector)
function create_test_problem()
    dummy_tensors_to_vars = [[1, 2], [2, 3]]
    # Use BitVector format for tensor data (true = satisfied)
    dummy_tensor_data = [
        BitVector(ones(Bool, 4)),  # All configs satisfy
        BitVector(ones(Bool, 4))
    ]
    static = BooleanInference.setup_problem(3, dummy_tensors_to_vars, dummy_tensor_data)
    return TNProblem(static)
end

@testset "basic problem creation" begin
    problem = create_test_problem()
    @test length(problem.static.vars) == 3
    @test length(problem.static.tensors) == 2
    @test count_unfixed(problem) >= 0
end

@testset "integration test with simple SAT" begin
    # Test with a simple SAT problem
    @bools a b c d
    cnf = ∧(∨(a, b), ∨(¬a, c), ∨(c, d))
    sat = Satisfiability(cnf; use_constraints=true)
    problem = setup_from_sat(sat)

    # Test basic properties
    @test problem isa TNProblem
    @test count_unfixed(problem) > 0

    # Test solving with simple strategy
    br_strategy = BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MostOccurrenceSelector(1, 2),
        measure=NumUnfixedVars()
    )
    result = bbsat!(problem, br_strategy, NoReducer())
    @test !isnothing(result)
    @test result isa Result
end
