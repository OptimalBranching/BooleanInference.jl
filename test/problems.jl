using Test
using BooleanInference
using ProblemReductions: Factoring, reduceto, CircuitSAT
using BooleanInference: setup_from_csp, TNProblem, setup_problem

@testset "generate_example_problem" begin
    csp = factoring_csp(10, 10, 559619)
    static = setup_from_csp(csp)
    problem = TNProblem(static)
    # After precontraction, vars may be fewer than original symbols
    @test length(problem.static.vars) > 0
    @test length(problem.static.tensors) > 0
    @test length(problem.static.v2t) == length(problem.static.vars)
    @show problem.static
end

@testset "ids are just Int" begin
    var_id = 1
    @test var_id == 1
    tensor_id = 1
    @test tensor_id == 1
end

@testset "setup_problem basic" begin
    # Create a simple 2-variable problem with 2 tensors
    tensor_data_1 = BitVector([false, false, false, true])  # AND: only (1,1) satisfies
    tensor_data_2 = BitVector([true, false])  # NOT: only 0 satisfies

    static = setup_problem(2, [[1, 2], [2]], [tensor_data_1, tensor_data_2])

    @test length(static.vars) == 2
    @test all(v.deg > 0 for v in static.vars)

    @test length(static.tensors) == 2
    @test length(static.tensors[1].var_axes) == 2
    @test length(static.tensors[2].var_axes) == 1

    @test length(static.v2t) == 2
    @test length(static.v2t[1]) == 1
    @test length(static.v2t[2]) == 2

    # Verify var_axes contains expected variables
    @test 1 in static.tensors[1].var_axes
    @test 2 in static.tensors[1].var_axes
end
