using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using Random
using ProblemReductions
using BooleanInference
using OptimalBranchingCore

result_dir = resolve_results_dir("factoring")

println("=" ^80)
println("Generating Factoring Datasets")
println("=" ^80)

configs = [
    FactoringConfig(8, 8),
    FactoringConfig(10, 10),
    FactoringConfig(12, 12),
    FactoringConfig(14, 14),
    FactoringConfig(16, 16),
    FactoringConfig(18, 18),
    # FactoringConfig(20, 20),
]

paths = generate_factoring_datasets(configs; per_config=20, include_solution=true, force_regenerate=false)

# bsconfig = BranchingStrategy(
#     table_solver=TNContractionSolver(),
#     selector=BooleanInference.MinGammaSelector(3,5,TNContractionSolver(), GreedyMerge()),
#     measure=NumHardTensors(),
#     set_cover_solver=GreedyMerge()
# )
# times, branches, _ = benchmark_dataset(FactoringProblem, paths[1]; solver=BooleanInferenceSolver(;bsconfig, show_stats=false), verify=true,save_result=result_dir)

for path in paths
    for n in 1:5
        println("MostOccurrenceSelector(3, $n)")
        bsconfig = BranchingStrategy(
            table_solver=TNContractionSolver(),
            selector=MostOccurrenceSelector(3,n),
            measure=NumHardTensors(),
            set_cover_solver=GreedyMerge()
        )
        times, branches, _ = benchmark_dataset(FactoringProblem, path; solver=BooleanInferenceSolver(;bsconfig, show_stats=false), verify=true, save_result=result_dir)
    end
end


times, branches, _ = benchmark_dataset(FactoringProblem, paths[1]; 
    solver=KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0), 
    verify=false, 
    save_result=result_dir)

times, branches, _ = benchmark_dataset(FactoringProblem, paths[1]; 
    solver=MinisatSolver(minisat_path="/opt/homebrew/bin/minisat", timeout=300.0), 
    verify=true, 
    save_result=result_dir)
