using Test
using BooleanInference
using BooleanInference: TNProblem, TNContractionSolver, MostOccurrenceSelector, NumUnfixedVars, setup_from_tensor_network, setup_problem, select_variables, get_cached_region, last_branch_problem, reset_last_branch_problem!, has_last_branch_problem, get_var_value, bits_to_int
using BooleanInference: BranchingStrategy, NoReducer
using OptimalBranchingCore: Clause
using OptimalBranchingCore: branching_table, branch_and_reduce
using ProblemReductions: Factoring, reduceto, CircuitSAT, read_solution
using GenericTensorNetworks
using TropicalNumbers: Tropical
# using Logging

# ENV["JULIA_DEBUG"] = "BooleanInference"

@testset "branch" begin
    # fproblem = Factoring(16, 16, 3363471157)
    fproblem = Factoring(10, 10, 559619)

    circuit_sat = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)

    tn = GenericTensorNetwork(problem)
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
    @test !has_last_branch_problem(tn_problem)
    br_strategy = BranchingStrategy(table_solver = TNContractionSolver(1,2), selector = MostOccurrenceSelector(), measure = NumUnfixedVars())
    res = branch_and_reduce(tn_problem, br_strategy, NoReducer(), Tropical{Float64}; show_progress=false)
    @show res
    if res != Tropical(-Inf)
        @test has_last_branch_problem(tn_problem)
        res = last_branch_problem(tn_problem)
        @test res.n_unfixed == 0
        # @show circuit_sat.q, circuit_sat.p

        a = get_var_value(res, circuit_sat.q)
        b = get_var_value(res, circuit_sat.p)
        # @show a, b
        @test bits_to_int(a) * bits_to_int(b) == 559619
    end
    clear_all_region_caches!()
end

@testset "commit_branch" begin
	@bools a b c d e f g
	cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
	tn_problem = BooleanInference.setup_from_cnf(cnf)
	new_problem, _ = BooleanInference.commit_branch(tn_problem, Clause(0b110, 0b100), [1, 2, 3])
    @test new_problem.n_unfixed == 5
end
