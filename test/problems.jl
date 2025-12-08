using Test
using BooleanInference
using ProblemReductions: Factoring, reduceto, CircuitSAT
using BooleanInference: setup_from_csp, TNProblem, setup_problem

@testset "generate_example_problem" begin
    csp = factoring_csp(10, 10, 559619)
    static = setup_from_csp(csp)
    problem = TNProblem(static)
    @test length(problem.static.vars) == length(csp.symbols)
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

# @testset "setup_problem" begin
#     var_num = 2
#     tensors_to_vars = [[1, 2], [2]]
#     tensor_data = [
#         [Tropical(0.0), Tropical(0.0), Tropical(0.0), Tropical(1.0)],  # AND: [0,0,0,1]
#         [Tropical(1.0), Tropical(0.0)]  # NOT: [1,0]
#     ]

#     tn = setup_problem(var_num, tensors_to_vars, tensor_data)

#     @test length(tn.vars) == 2
#     @test all(v.deg > 0 for v in tn.vars)

#     @test length(tn.tensors) == 2
#     @test length(tn.tensors[1].var_axes) == 2
#     @test length(tn.tensors[2].var_axes) == 1

#     @test length(tn.v2t) == 2
#     @test length(tn.v2t[1]) == 1
#     @test length(tn.v2t[2]) == 2

#     # Verify var_axes can replace t2v
#     @test length(tn.tensors[1].var_axes) == 2
#     @test 1 in tn.tensors[1].var_axes
#     @test 2 in tn.tensors[1].var_axes
# end

# @testset "setup_from_tensor_network" begin
#     tn = GenericTensorNetwork(generate_example_problem())
#     tn_static = setup_from_tensor_network(tn)
#     tn_problem = TNProblem(tn_static)
# end
