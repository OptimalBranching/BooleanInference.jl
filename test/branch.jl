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


@testset "branch_and_reduce" begin
	@bools a b c d e f g
	cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
	ans, vals = solvebip(Satisfiability(cnf))
	@test ans
end

@testset "benchmark" begin
	table_solver = TNContractionSolver()
	reducer = NoReducer()
	for selector in [KNeighborSelector(1, 1), KNeighborSelector(2, 1), KNeighborSelector(1, 2), KNeighborSelector(2, 2)]
		for measure in [NumOfVertices(), NumOfClauses(), NumOfDegrees()]
            println("$measure,$selector")
			solve_factoring(8, 8, 1019 * 1021; bsconfig = BranchingStrategy(; table_solver, selector, measure), reducer)
		end
	end
end

@testset "interface" begin
    solve_factoring(8, 8, 1019 * 1021; bsconfig = BranchingStrategy(; table_solver= TNContractionSolver(), selector=KNeighborSelector(1, 1), measure=NumOfDegrees()), reducer= NoReducer())
    solve_factoring(5, 5, 899; bsconfig = BranchingStrategy(; table_solver= TNContractionSolver(), selector=KNeighborSelector(1, 1), measure=NumOfDegrees()), reducer= NoReducer())
end