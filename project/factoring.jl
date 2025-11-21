using Test
using BooleanInference
using BooleanInference: TNProblem, TNContractionSolver, MostOccurrenceSelector, NumUnfixedVars, setup_from_tensor_network, setup_problem, select_variables, get_var_value, bits_to_int
using BooleanInference: BranchingStrategy, NoReducer
using OptimalBranchingCore: Clause
using OptimalBranchingCore: branching_table, branch_and_reduce
using ProblemReductions: Factoring, reduceto, CircuitSAT, read_solution
using GenericTensorNetworks
using OptimalBranchingCore
using TropicalNumbers: Tropical

# fproblem = Factoring(16, 16, 3363471157)
fproblem = Factoring(5,5,256)
circuit_sat = reduceto(CircuitSAT, fproblem)
problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)

tn = GenericTensorNetwork(problem)
tn_static = setup_from_tensor_network(tn)
tn_problem = TNProblem(tn_static)
br_strategy = BranchingStrategy(
    table_solver = TNContractionSolver(), 
    selector = MinGammaSelector(1,2,TNContractionSolver(), OptimalBranchingCore.GreedyMerge()), 
    # selector = MostOccurrenceSelector(1,2),
    measure = NumUnfixedVars(),
    set_cover_solver = OptimalBranchingCore.GreedyMerge()
)
res = branch_and_reduce(tn_problem, br_strategy, NoReducer(), Tropical{Float64}; show_progress=false)
@show res