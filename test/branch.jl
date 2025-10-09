using BooleanInference
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using Test
using BooleanInference.GenericTensorNetworks.ProblemReductions
using BooleanInference.OptimalBranchingCore: Clause, BranchingStrategy

@testset "apply_branch" begin
	@bools a b c d e f g
	cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
	bip, syms = convert_cnf_to_bip(cnf)
	bs = initialize_branching_status(bip)
	bs = BooleanInference.apply_branch(bip, bs, Clause(0b110, 0b100), [1, 2, 3])
	@test bs.undecided_literals == [2, -1, 2, -1]
	@test bs.config == 4
	@test bs.decided_mask == 6
end

@testset "num_of_2sat_clauses" begin
	@bools a b c d e f g
	cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
	bip, syms = convert_cnf_to_bip(cnf)
	bs = initialize_branching_status(bip)
	@test BooleanInference.num_of_2sat_clauses(bs) == 2
	@test BooleanInference.OptimalBranchingCore.measure(bs, WeightedClauseArityMeasure()) == 2
end