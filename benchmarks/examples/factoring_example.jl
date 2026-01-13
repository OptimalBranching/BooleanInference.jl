using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using Random
using ProblemReductions
using BooleanInference
using OptimalBranchingCore
# using Gurobi

# const env = Gurobi.Env()

result_dir = resolve_results_dir("factoring")

println("="^80)
println("Generating Factoring Datasets")
println("="^80)

configs = [
    # FactoringConfig(8, 8),
    # FactoringConfig(10, 10),
    # FactoringConfig(12, 12),
    FactoringConfig(14, 14),
    # FactoringConfig(16, 16),
    # FactoringConfig(18, 18),
    # FactoringConfig(20, 20),
    # FactoringConfig(22, 22),
]

paths = generate_factoring_datasets(configs; per_config=20, include_solution=true, force_regenerate=false)

# bsconfig = BranchingStrategy(
#     table_solver=TNContractionSolver(),
#     selector=BooleanInference.MinGammaSelector(3,5,TNContractionSolver(), GreedyMerge()),
#     measure=NumHardTensors(),
#     set_cover_solver=GreedyMerge()
# )
# times, branches, _ = benchmark_dataset(FactoringProblem, paths[1]; solver=BooleanInferenceSolver(;bsconfig, show_stats=false), verify=true,save_result=result_dir)

# for path in paths
#     for n in 1:5
#         println("MostOccurrenceSelector(3, $n)")
#         bsconfig = BranchingStrategy(
#             table_solver=TNContractionSolver(),
#             selector=MostOccurrenceSelector(3,n),
#             measure=NumUnfixedVars(),
#             set_cover_solver=GreedyMerge()
#         )
#         times, branches, _ = benchmark_dataset(FactoringProblem, path; solver=BooleanInferenceSolver(;bsconfig, show_stats=false), verify=true, save_result=result_dir)
#     end
# end

for path in paths
    # times, branches, _ = benchmark_dataset(FactoringProblem, path; solver=KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0), verify=false, save_result=result_dir)
    # times, branches, _ = benchmark_dataset(FactoringProblem, path; solver=MinisatSolver(minisat_path="/opt/homebrew/bin/minisat", timeout=300.0), verify=false, save_result=result_dir)
    times, branches, _ = benchmark_dataset(FactoringProblem, path; solver=BooleanInferenceBenchmarks.IPSolver(Gurobi.Optimizer, env), verify=true, save_result=result_dir)
    # times, branches, _ = benchmark_dataset(FactoringProblem, path; solver=XSATSolver(csat_path=joinpath(dirname(@__DIR__), "artifacts", "bin", "csat"), timeout=300.0), verify=true, save_result=result_dir)
end

inst = FactoringInstance(22,22,11290185688783)
# ========================================
# method 1: BooleanInference Solver (TN-based)
# ========================================
solver = Solvers.BI(selector=MostOccurrenceSelector(3, 4), set_cover_solver=GreedyMerge(), show_stats=true)
result = solve_instance(FactoringProblem, inst, solver)
println("BI Result: $result")

# ========================================
# method 2: Kissat (CDCL SAT solver)
# ========================================
solver = Solvers.Kissat(timeout=60.0, quiet=false)
result2 = solve_instance(FactoringProblem, inst, solver)
println("Kissat Result: status=$(result2.status), decisions=$(result2.decisions)")

# ========================================
# method 3: Minisat
# ========================================
solver = Solvers.Minisat(timeout=60.0, quiet=false)
result3 = solve_instance(FactoringProblem, inst, solver)
println("Minisat Result: status=$(result3.status), decisions=$(result3.decisions)")

# ========================================
# method 4: CryptoMiniSat
# ========================================
solver = Solvers.CryptoMiniSat(timeout=60.0, quiet=false)
result4 = solve_instance(FactoringProblem, inst, solver)
println("CryptoMiniSat Result: status=$(result4.status), decisions=$(result4.decisions)")

# ========================================
# method 5: Cube and Conquer (march_cu + kissat)
# ========================================
solver = Solvers.CnC()
result4 = solve_instance(FactoringProblem, inst, solver)
println("MarchCu Result: status=$(result4.status), cubes/decisions=$(result4.decisions)")
