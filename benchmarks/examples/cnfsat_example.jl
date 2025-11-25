using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using ProblemReductions
using BooleanInference
using BooleanInference.OptimalBranchingCore

dataset_path = joinpath(@__DIR__, "..", "data", "CNF", "random")

bsconfig = BranchingStrategy(
    table_solver=TNContractionSolver(),
    # selector=MinGammaSelector(1,2,TNContractionSolver(), GreedyMerge()),
    selector=MostOccurrenceSelector(1,3),
    measure=NumUnfixedVars(),
    set_cover_solver=GreedyMerge()
)

result = benchmark_dataset(
    CNFSATProblem,
    dataset_path;
    solver=BooleanInferenceSolver(;bsconfig),
    verify=true
)

test_file = joinpath(dataset_path, "3sat1.cnf")
test_instance = parse_cnf_file(test_file)
result = solve_instance(CNFSATProblem, test_instance, BooleanInferenceSolver(;bsconfig, show_stats=true))
@show result