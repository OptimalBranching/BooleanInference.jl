using Test
using BooleanInference
using BooleanInference: TNProblem, TNContractionSolver, MostOccurrenceSelector, NumUnfixedVars, setup_from_tensor_network, setup_problem, select_variables, get_var_value, bits_to_int, bbsat!, MinGammaSelector
using BooleanInference: BranchingStrategy, NoReducer
using OptimalBranchingCore: Clause
using OptimalBranchingCore: branching_table, branch_and_reduce
using ProblemReductions: Factoring, reduceto, CircuitSAT, read_solution
using GenericTensorNetworks
using OptimalBranchingCore
using TropicalNumbers: Tropical

# fproblem = Factoring(16, 16, 3363471157)
fproblem = Factoring(10,10,559619)
circuit_sat = reduceto(CircuitSAT, fproblem)
problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)

tn = GenericTensorNetwork(problem)
tn_static = setup_from_tensor_network(tn)
tn_problem = TNProblem(tn_static)
br_strategy = BranchingStrategy(
    table_solver = TNContractionSolver(), 
    selector = MinGammaSelector(1,2,TNContractionSolver(), OptimalBranchingCore.GreedyMerge()), 
    # selector = MostOccurrenceSelector(1,2),
    measure = BooleanInference.NumUnfixedVars(),
    set_cover_solver = OptimalBranchingCore.GreedyMerge()
)
@time res = bbsat!(tn_problem, br_strategy, NoReducer())
if res.found
    a = get_var_value(res.solution, circuit_sat.q)
    b = get_var_value(res.solution, circuit_sat.p)
    @show bits_to_int(a), bits_to_int(b), res.stats
    reset_problem!(tn_problem)
end