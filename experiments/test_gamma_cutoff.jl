"""
Test GammaRatioCutoff with different thresholds
"""

using BooleanInference
using BooleanInference: setup_from_sat
using OptimalBranchingCore: BranchingStrategy, GreedyMerge
using ProblemReductions: reduceto, CircuitSAT, Factoring

N = BigInt(3363471157)  # 59743 × 56299
n, m = 16, 16

bsconfig = BranchingStrategy(
    table_solver = TNContractionSolver(),
    selector = MostOccurrenceSelector(3, 4),
    measure = NumUnfixedTensors(),
    set_cover_solver = GreedyMerge()
)
reducer = GammaOneReducer(40)

println("="^50)
println("GammaRatioCutoff Test")
println("="^50)
println("\nThreshold | Cubes")
println("-"^25)

for threshold in [0.95, 0.96, 0.97, 0.975, 0.98, 0.985, 0.99, 0.995]
    reduction = reduceto(CircuitSAT, Factoring(n, m, N))
    circuit_sat = CircuitSAT(reduction.circuit.circuit; use_constraints=true)
    tn_problem = setup_from_sat(circuit_sat)

    result = generate_cubes!(tn_problem, bsconfig, reducer, GammaRatioCutoff(threshold))
    println("  $(threshold)     | $(result.n_cubes)")
end

println("\n" * "="^50)
println("ProductCutoff Comparison")
println("="^50)
println("\nThreshold | Cubes")
println("-"^25)

for threshold in [5000, 10000, 15000, 20000, 25000, 30000]
    reduction = reduceto(CircuitSAT, Factoring(n, m, N))
    circuit_sat = CircuitSAT(reduction.circuit.circuit; use_constraints=true)
    tn_problem = setup_from_sat(circuit_sat)

    result = generate_cubes!(tn_problem, bsconfig, reducer, ProductCutoff(threshold))
    println("  $(threshold)     | $(result.n_cubes)")
end
