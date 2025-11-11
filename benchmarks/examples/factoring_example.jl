using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using Random

# using Gurobi
# const env = Gurobi.Env()

# ----------------------------------------
# Example 1: Generate datasets
# ----------------------------------------

println("=" ^80)
println("Generating Factoring Datasets")
println("=" ^80)

configs = [
    # FactoringConfig(10, 10),
    # FactoringConfig(12, 12),
    # FactoringConfig(14, 14),
    # FactoringConfig(16, 16),
    # FactoringConfig(18, 18),
    # FactoringConfig(20, 20),
    # FactoringConfig(22, 22),
    FactoringConfig(24, 24)
]

paths = generate_factoring_datasets(configs; per_config=5, include_solution=true, force_regenerate=false)

# ----------------------------------------
# Example 2: Run benchmark on a single dataset
# ----------------------------------------

# println("\n" * "=" ^80)
# println("Running Benchmark")
# println("=" ^80)

# # result = benchmark_dataset(FactoringProblem, paths[1]; solver=XSATSolver(;yosys_path="/opt/homebrew/bin/yosys"))
# result = benchmark_dataset(FactoringProblem, paths[1]; solver=IPSolver(Gurobi.Optimizer, env))

# if !isnothing(result)
#     println("\nResults:")
#     println("  Dataset: $(result["dataset_path"])")
#     println("  Instances tested: $(result["instances_tested"])")
#     println("  Accuracy: $(round(result["accuracy_rate"]*100, digits=1))%")
#     println("  Median time: $(result["median_time"]) seconds")
# end

# ----------------------------------------
# Example 3: Compare solvers
# ----------------------------------------

println("\n" * "=" ^80)
println("Comparing Solvers")
println("=" ^80)

# results = run_solver_comparison(FactoringProblem, paths, solvers=[XSATSolver(;yosys_path="/opt/homebrew/bin/yosys"), BooleanInferenceSolver()])
results = run_solver_comparison(FactoringProblem, paths, solvers=[XSATSolver(;yosys_path="/opt/homebrew/bin/yosys", timeout=600.0)])
# results = run_solver_comparison(FactoringProblem, paths, solvers=[KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0), MinisatSolver(minisat_path="/opt/homebrew/bin/minisat", timeout=300.0)])
print_solver_comparison_summary(results)

