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

    tn = GenericTensorNetwork(sat)
    circuit_info = compute_circuit_info(sat)
    tensor_info = map_tensor_to_circuit_info(tn, circuit_info, sat)

    @test circuit_info.depths == [4, 3, 4, 2, 1]
    @test circuit_info.fanin == [[:a, :b], [:x, :c], [:m, :n], [:y, :f], [:e]]
    @test circuit_info.fanout == [[:x], [:y], [:c], [:e], [Symbol("true")]]

end


