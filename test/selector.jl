using BooleanInference
using Test
using BooleanInference.ProblemReductions
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using BooleanInference.OptimalBranchingCore: select_variables,apply_branch,Clause

@testset "subhg" begin
    @bools a b c d e f g
	cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
	bip, syms = cnf2bip(cnf)
    bs = initialize_branching_status(bip)
	bsnew = reduce_problem(bip, bs, collect(1:5),DeductionReducer())
    subhe2v,elist = subhg(bip,bsnew)

    @test subhe2v == [[2, 3, 4],[5, 6],[2, 7]]
    @test elist == [1,3,4]
end

@testset "neighboring" begin
    @bools a b c d e
    cnf = ∧(∨(b), ∨(a,¬c), ∨(d,¬b), ∨(¬c,¬d), ∨(a,e), ∨(a,e,¬c))
    bip,syms = cnf2bip(cnf)

    subbip = neighboring(bip.he2v,1)
    @test subbip == [1, 4]

    subbip = neighboring(bip.he2v,2)
    @test subbip == [2, 3, 5]
end

@testset "k_neighboring" begin
    @bools a b c d e
    cnf = ∧(∨(b), ∨(a,¬c), ∨(d,¬b), ∨(¬c,¬d), ∨(a,e), ∨(a,e,¬c))
    bip,syms = cnf2bip(cnf)

    subbip = k_neighboring(bip.he2v,1,2)
    @test subbip == [1, 3, 4]

    subbip = k_neighboring(bip.he2v,2,2)
    @test subbip == [2, 3, 4, 5]
end

@testset "KNeighborSelector,neighbor_subbip" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
    sat = Satisfiability(cnf)
    bip,syms = sat2bip(sat)
    bs = initialize_branching_status(bip)

    subbip = select_variables(bip,bs, BooleanInference.NumOfVertices(),KNeighborSelector(4,3))
    @test subbip.vs == collect(1:7)
    @test subbip.edges == collect(1:4)
    @test subbip.outside_vs_ind == []
end

@testset "KaHyParSelector" begin
    fproblem = Factoring(8, 8, 251*249)
    res = reduceto(CircuitSAT,fproblem)
    
    bip,syms = sat2bip(res.circuit)
    bs = initialize_branching_status(bip)
    subbip = select_variables(bip,bs, BooleanInference.NumOfVertices(),KaHyParSelector(10))
end

@testset "SubBIP" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
    bip, syms = cnf2bip(cnf)
    bs = initialize_branching_status(bip)
    subbip = BooleanInference.SubBIP(bip,bs,[1,2,3,4])

    bs = apply_branch(bip,bs,Clause(0b1, 0b1),[1])
    subbip = BooleanInference.SubBIP(bip,bs,[2,3,4,5])
end