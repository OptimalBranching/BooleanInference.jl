using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using Random
using ProblemReductions
using BooleanInference
using BooleanInference.OptimalBranchingCore
using BooleanInference: HardSetSize, NumHardTensors

configs = [
    FactoringConfig(8, 8),
]

paths = generate_factoring_datasets(configs; per_config=20, include_solution=true, force_regenerate=false)

bsconfig = BranchingStrategy(
    table_solver=TNContractionSolver(),
    selector=MinGammaSelector(3,5,TNContractionSolver(), GreedyMerge()),
    # selector=MostOccurrenceSelector(1,2),
    measure=HardSetSize(),
    # measure=NumHardTensors(),
    set_cover_solver=GreedyMerge()
)
result = benchmark_dataset(FactoringProblem, paths[1]; solver=BooleanInferenceSolver(;bsconfig), verify=true)
times = result["all_time"]
branching_stats = result["all_results"]
branches = Int[]
for res in branching_stats
    push!(branches, res[3].total_visited_nodes)
end
println(times)
println(branches)


