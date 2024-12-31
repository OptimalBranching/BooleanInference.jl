using BooleanInference
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using Test
using BooleanInference.GenericTensorNetworks.ProblemReductions

@testset "clause2tensors" begin
    @bools a b c d
	cnf = ∧(∨(a, b, ¬c))
	bip, syms = cnf2bip(cnf)
    tensor,lits = BooleanInference.clause2tensors([1,2,-3])
    @test bip.tensors[1]== tensor

    cnf = ∧(∨(¬a, b, ¬c, d))
	bip, syms = cnf2bip(cnf)
    tensor,lits = BooleanInference.clause2tensors([-1,2,-3,4])
    @test bip.tensors[1]== tensor
end

@testset "readcnf" begin
    @bools a b c d e f
	cnf = ∧(∨(a, b, c), ∨(d, e), ∨(a,c,¬e), ∨(¬b, c, e,f))
	bip, syms = cnf2bip(cnf)
    bip2 = readcnf("datas/test.cnf")
    @test bip.he2v == bip2.he2v
    @test bip.tensors == bip2.tensors
    @test bip.literal_num == bip2.literal_num
    @test bip.v2he == bip2.v2he
end

@testset "solvecnf" begin
    solvecnf("datas/test.cnf")
end