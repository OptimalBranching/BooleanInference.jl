using Test
using BooleanInference
using ProblemReductions: Factoring, reduceto, CircuitSAT
using GenericTensorNetworks
using BooleanInference: setup_from_cnf, k_neighboring
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬

function generate_example_problem()
    fproblem = Factoring(12, 12, 10395529)
    res = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(res.circuit.circuit; use_constraints=true)
    return problem
end

@testset "knn" begin
    problem = generate_example_problem()
    tn = GenericTensorNetwork(problem)
    tn = BooleanInference.setup_from_tensor_network(tn)
    doms = BooleanInference.init_doms(tn)
    region = BooleanInference.k_neighboring(tn, doms, 1; k=2, max_tensors=10)
    @show region
end

@testset "original_test_for_neighboring" begin
    @bools a b c d e f g
    cnf = ∧(∨(b), ∨(a,¬c), ∨(d,¬b), ∨(¬c,¬d), ∨(a,e), ∨(a,e,¬c))
    problem = setup_from_cnf(cnf)
    # Use unpropagated doms for testing k_neighboring
    doms = BooleanInference.init_doms(problem.static)
    region = k_neighboring(problem.static, doms, 1; max_tensors=100, k=1)
    @test region.tensors == [1, 3]
    @test Set(region.vars) == Set([1, 4])

    region = k_neighboring(problem.static, doms, 2; max_tensors=100, k=1)
    @test region.tensors == [2, 5, 6]
    @test Set(region.vars) == Set([2, 3, 5])
end


@testset "original_test_for_k_neighboring" begin
    @bools a b c d e
    cnf = ∧(∨(b), ∨(a,¬c), ∨(d,¬b), ∨(¬c,¬d), ∨(a,e), ∨(a,e,¬c))
    problem = setup_from_cnf(cnf)
    # Use unpropagated doms for testing k_neighboring
    doms = BooleanInference.init_doms(problem.static)
    region = k_neighboring(problem.static, doms, 1; max_tensors=100, k=2)
    @test region.tensors == [1, 3, 4]
    @test Set(region.vars) == Set([1, 3, 4])

    region = k_neighboring(problem.static, doms, 2; max_tensors=100, k=2)
    @test region.tensors == [2, 4, 5, 6]
    @test Set(region.vars) == Set([2, 3, 4, 5])
end