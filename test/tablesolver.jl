using BooleanInference
using Test
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using BooleanInference.OptimalBranchingCore: select_variables
using BooleanInference.OptimalBranchingCore.BitBasis
# using BooleanInference:SubBIP

# @testset "branching_table" begin
#     @bools a b c d e f g
#     cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
#     bip,syms = convert_cnf_to_bip(cnf)
#     bs = initialize_branching_status(bip)

#     subbip = SubBIP(bip,bs,[1,2,3,4,5])
#     tbl = BooleanInference.branching_table(bip, bs, BooleanInference.TNContractionSolver(), subbip)

#     @test subbip.outside_vs_ind == [2,5]
#     test_tag = true
#     for vec in tbl.table
#         for cl in vec
#             test_tag = (readbit(cl,2) == readbit(vec[1],2)) && test_tag
#             test_tag = (readbit(cl,5) == readbit(vec[1],5)) && test_tag
#         end
#     end
#     @test test_tag
# end