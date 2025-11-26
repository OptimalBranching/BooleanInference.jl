using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using Random
using ProblemReductions
using BooleanInference
using OptimalBranchingCore

using Gurobi
const env = Gurobi.Env()

# ----------------------------------------
# Example 1: Generate datasets
# ----------------------------------------

println("=" ^80)
println("Generating Factoring Datasets")
println("=" ^80)



configs = [
    # FactoringConfig(8, 8),
    # FactoringConfig(10, 10),
    # FactoringConfig(12, 12),
    FactoringConfig(14, 14),
    # FactoringConfig(16, 16),
    # FactoringConfig(18, 18),
    # FactoringConfig(20, 20),
]

paths = generate_factoring_datasets(configs; per_config=20, include_solution=true, force_regenerate=false)

bsconfig = BranchingStrategy(
    table_solver=TNContractionSolver(),
    selector=BooleanInference.MinGammaSelector(3,5,TNContractionSolver(), GreedyMerge()),
    # selector=MostOccurrenceSelector(1,2),
    measure=NumHardTensors(),
    set_cover_solver=GreedyMerge()
)
# Benchmark for BooleanInference Solver
result = benchmark_dataset(FactoringProblem, paths[1]; solver=BooleanInferenceSolver(;bsconfig, show_stats=true), verify=true)
times = result["all_time"]
branching_stats = result["all_results"]
branches = Int[]
for res in branching_stats
    push!(branches, res[3].total_visited_nodes)
end
println(times)
println(branches)


bsconfig = BranchingStrategy(
    table_solver=TNContractionSolver(),
    # selector=BooleanInference.MinGammaSelector(2,3,TNContractionSolver(), GreedyMerge()),
    selector=MostOccurrenceSelector(2,4),
    measure=NumHardTensors(),
    set_cover_solver=GreedyMerge()
)
# Benchmark for BooleanInference Solver
result = benchmark_dataset(FactoringProblem, paths[1]; solver=BooleanInferenceSolver(;bsconfig), verify=true)
times = result["all_time"]
branching_stats = result["all_results"]
branches = Int[]
for res in branching_stats
    push!(branches, res[3].total_visited_nodes)
end
println(times)
println(branches)

#Benchmark for Kissat Solver
result = benchmark_dataset(FactoringProblem, paths[1]; solver=KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0), verify=false)
times = result["all_time"]
branching_stats = result["all_results"]
branches = Int[]
for res in branching_stats
    push!(branches, res.decisions)
end
println(times)
println(branches)

result = benchmark_dataset(FactoringProblem, paths[1]; solver=MinisatSolver(minisat_path="/opt/homebrew/bin/minisat", timeout=300.0), verify=false)
times = result["all_time"]
branching_stats = result["all_results"]
branches = Int[]
for res in branching_stats
    push!(branches, res.decisions)
end
println(times)
println(branches)

test_instance = FactoringInstance(14,14,183974111)
@time result = solve_instance(FactoringProblem, test_instance, BooleanInferenceSolver(;bsconfig, show_stats=true))
result = solve_instance(FactoringProblem, test_instance, KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0, quiet=false))
result = solve_instance(FactoringProblem, test_instance, MinisatSolver(minisat_path="/opt/homebrew/bin/minisat", timeout=300.0, quiet=false))
# @show result


