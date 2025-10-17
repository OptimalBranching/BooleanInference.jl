using Test
using BooleanInference
using ProblemReductions: Factoring, reduceto, CircuitSAT
using GenericTensorNetworks
using BenchmarkTools

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
    ws = BooleanInference.HopWorkspace(length(tn.vars), length(tn.tensors))
    region = BooleanInference.k_neighboring(tn, ws, Int32(1); k=2, max_tensors=10)
    @show region

end