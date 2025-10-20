using Test
using BooleanInference
using ProblemReductions: Factoring, reduceto, CircuitSAT
using GenericTensorNetworks
using BooleanInference: setup_from_tensor_network, TNProblem, DynamicWorkspace, setup_problem
using TropicalNumbers: Tropical

function generate_example_problem()
    fproblem = Factoring(2, 2, 6)
    res = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(res.circuit.circuit; use_constraints=true)
    return problem
end

@testset "generate_example_problem" begin
    problem = generate_example_problem()
    tn = GenericTensorNetwork(problem)
    problem = setup_from_tensor_network(tn)
    @test length(problem.vars) == length(tn.problem.symbols)
    @test length(problem.tensors) > 0
    @test length(problem.v2t) == length(problem.vars)
    @test length(problem.t2v) == length(problem.tensors)
    @show problem
end

@testset "ids are just Int" begin
    var_id = 1
    @test var_id == 1
    tensor_id = 1
    @test tensor_id == 1
end

@testset "setup_problem" begin
    var_num = 2
    tensors_to_vars = [[1, 2], [2]]
    tensor_data = [
        [Tropical(0.0), Tropical(0.0), Tropical(0.0), Tropical(1.0)],  # AND: [0,0,0,1]
        [Tropical(1.0), Tropical(0.0)]  # NOT: [1,0]
    ]
    
    tn = setup_problem(var_num, tensors_to_vars, tensor_data)
    
    @test length(tn.vars) == 2
    @test all(v.dom_size == 2 for v in tn.vars)
    
    @test length(tn.tensors) == 2
    @test length(tn.tensors[1].var_axes) == 2
    @test length(tn.tensors[2].var_axes) == 1
    
    @test length(tn.v2t) == 2
    @test length(tn.v2t[1]) == 1
    @test length(tn.v2t[2]) == 2
    
    @test length(tn.t2v) == 2
    @test length(tn.t2v[1]) == 2
    @test length(tn.t2v[2]) == 1
    
    @test haskey(tn.axis_of_t, (1, 1))
    @test haskey(tn.axis_of_t, (1, 2))
    @test haskey(tn.axis_of_t, (2, 2))
end

@testset "setup_from_tensor_network" begin
    tn = GenericTensorNetwork(generate_example_problem())
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
end
