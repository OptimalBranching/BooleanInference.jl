using BooleanInference
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using Test
using BooleanInference.GenericTensorNetworks.ProblemReductions

@testset "initialize_branching_status" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
    bip, syms = cnf2bip(cnf)
    branching_status = initialize_branching_status(bip)
    @test branching_status.undecided_literals == [4,4,2,2,1]
    @test branching_status.config == 0
    @test branching_status.decided_mask == 0
end