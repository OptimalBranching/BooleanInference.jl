using BooleanInference
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using Test
using BooleanInference.GenericTensorNetworks.ProblemReductions
using BooleanInference.OptimalBranchingCore: apply_branch, branch_and_reduce, Clause, BranchingStrategy

@testset "apply_branch" begin
	@bools a b c d e f g
	cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
	bip, syms = cnf2bip(cnf)
	bs = initialize_branching_status(bip)
	bs = apply_branch(bip, bs, Clause(0b110, 0b100), [1, 2, 3])
	@test bs.undecided_literals == [2, -1, 2, -1]
	@test bs.config == 4
	@test bs.decided_mask == 6
end