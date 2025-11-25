using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using Random
using ProblemReductions
using BooleanInference
using BooleanInference.OptimalBranchingCore

using Gurobi
const env = Gurobi.Env()

# ----------------------------------------
# Example 1: Generate datasets
# ----------------------------------------

println("=" ^80)
println("Generating Factoring Datasets")
println("=" ^80)

configs = [
    # FactoringConfig(10, 10),
    # FactoringConfig(12, 12),
    FactoringConfig(14, 14),
    # FactoringConfig(16, 16),
    # FactoringConfig(18, 18),
    # FactoringConfig(20, 20),
    # FactoringConfig(22, 22),
    # FactoringConfig(24, 24)
]

paths = generate_factoring_datasets(configs; per_config=5, include_solution=true, force_regenerate=false)

println("\n" * "=" ^80)
println("Comparing Solvers")
println("=" ^80)

bsconfig = BranchingStrategy(
    table_solver=TNContractionSolver(),
    selector=MinGammaSelector(2,4,TNContractionSolver(), GreedyMerge()),
    # selector=MostOccurrenceSelector(2,4),
    measure=NumUnfixedVars(),
    set_cover_solver=GreedyMerge()
)

results = run_solver_comparison(FactoringProblem, paths, solvers=[XSATSolver(;yosys_path="/opt/homebrew/bin/yosys"), BooleanInferenceSolver(;bsconfig)])
# results = run_solver_comparison(FactoringProblem, paths, solvers=[XSATSolver(;yosys_path="/opt/homebrew/bin/yosys", timeout=600.0)])
# results = run_solver_comparison(FactoringProblem, paths, solvers=[KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0), MinisatSolver(minisat_path="/opt/homebrew/bin/minisat", timeout=300.0)])
# results = run_solver_comparison(FactoringProblem, paths, solvers=[IPSolver(Gurobi.Optimizer, env)])
print_solver_comparison_summary(results)


test_instance = FactoringInstance(12,12,10371761)
result = solve_instance(FactoringProblem, test_instance, BooleanInferenceSolver(;bsconfig, show_stats=true))
# @show result
# result = solve_instance(FactoringProblem, test_instance, KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0, quiet=false))
@show result
