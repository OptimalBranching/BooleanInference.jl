using BooleanInference
using Test
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using BooleanInference.OptimalBranchingCore: branching_table,select_variables


@testset "branching_table" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
    bip,syms = cnf2bip(cnf)
    bs = initialize_branching_status(bip)

    subbip = select_variables(bip,bs, BooleanInference.NumOfVertices(),KNeighborSelector(1))
    tbl = branching_table(bip, bs,BooleanInference.TNContractionSolver(), subbip)

    @test subbip.outside_vs_ind == [2,5]
    test_tag = true
    for vec in tbl.table
        for cl in vec
            test_tag = (readbit(cl,2) == readbit(vec[1],2)) && test_tag
            test_tag = (readbit(cl,5) == readbit(vec[1],5)) && test_tag
        end
    end
    @test test_tag
end