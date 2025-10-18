using Test
using BooleanInference
using BooleanInference: TNProblem, TNContractionSolver, LeastOccurrenceSelector, NumUnfixedVars, setup_from_tensor_network, setup_problem, select_variables, get_cached_region, last_branch_problem, reset_last_branch_problem!, has_last_branch_problem, get_var_value, bits_to_int
using BooleanInference: BranchingStrategy, NoReducer
using OptimalBranchingCore: branching_table, branch_and_reduce
using ProblemReductions: Factoring, reduceto, CircuitSAT, read_solution
using GenericTensorNetworks
using BenchmarkTools
using TropicalNumbers: Tropical
# using Logging

# ENV["JULIA_DEBUG"] = "BooleanInference"

@testset "branch" begin
    # fproblem = Factoring(12, 12, 10)
    fproblem = Factoring(2, 2, 4)
    circuit_sat = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)

    tn = GenericTensorNetwork(problem)
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
    @test !has_last_branch_problem(tn_problem)

    br_strategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = LeastOccurrenceSelector(2, 2), measure = NumUnfixedVars())

    @time res = branch_and_reduce(tn_problem, br_strategy, NoReducer(), Tropical{Float64}; show_progress=false)
    @show res
    if res != Tropical(-Inf)
        @test has_last_branch_problem(tn_problem)
        res = last_branch_problem(tn_problem)
        @test res.n_unfixed == 0
        # @show circuit_sat.q, circuit_sat.p

        a = get_var_value(res, circuit_sat.q)
        b = get_var_value(res, circuit_sat.p)
        # @show a, b
        @show bits_to_int(a), bits_to_int(b)
    end
end

# @testset "apply_branch" begin
# 	@bools a b c d e f g
# 	cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
# 	bip, syms = convert_cnf_to_bip(cnf)
# 	bs = initialize_branching_status(bip)
# 	bs = BooleanInference.apply_branch(bip, bs, Clause(0b110, 0b100), [1, 2, 3])
# 	@test bs.undecided_literals == [2, -1, 2, -1]
# 	@test bs.config == 4
# 	@test bs.decided_mask == 6
# end

# @testset "num_of_2sat_clauses" begin
# 	@bools a b c d e f g
# 	cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
# 	bip, syms = convert_cnf_to_bip(cnf)
# 	bs = initialize_branching_status(bip)
# 	@test BooleanInference.num_of_2sat_clauses(bs) == 2
# 	@test BooleanInference.OptimalBranchingCore.measure(bs, WeightedClauseArityMeasure()) == 2
# end