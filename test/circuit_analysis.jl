using BooleanInference
using TropicalNumbers
using ProblemReductions: @circuit, CircuitSAT
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using Test

@testset "circuit analysis" begin

    circuit = @circuit begin
        x = a ∨ b  # 4
        y = x ∧ c  # 3
        c = m ⊻ n  # 4
        e = y ∧ f  # 2
        e = true   # 1
    end

    sat = CircuitSAT(circuit; use_constraints=true)
    symbols = [sat.circuit.exprs[i].expr.head for i in 1:length(sat.circuit.exprs)]
    @test symbols == [:∨, :∧, :⊻, :∧, :var]

    # compute_circuit_info and map_tensor_to_circuit_info are currently not implemented
    # Skip these tests until the functions are re-implemented
    @test_skip "compute_circuit_info not yet implemented"
end
