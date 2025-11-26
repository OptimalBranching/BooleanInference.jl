using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using ProblemReductions
using BooleanInference
using BooleanInference.OptimalBranchingCore

dataset_path = joinpath(@__DIR__, "..", "data", "CNF", "random")

bsconfig = BranchingStrategy(
    table_solver=TNContractionSolver(),
    selector=MinGammaSelector(1,2,TNContractionSolver(), GreedyMerge()),
    # selector=MostOccurrenceSelector(1,2),
    measure=NumHardTensors(),
    set_cover_solver=GreedyMerge()
)

result = benchmark_dataset(
    CNFSATProblem,
    dataset_path;
    solver=BooleanInferenceSolver(;bsconfig),
    verify=true
)

test_file = joinpath(dataset_path, "3sat10.cnf")
test_instance = parse_cnf_file(test_file)
result = solve_instance(CNFSATProblem, test_instance, BooleanInferenceSolver(;bsconfig, show_stats=true))
result = solve_instance(CNFSATProblem, test_instance, KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0, quiet=false))

@show result

# === Branching Statistics ===
# Branching nodes: 19712
# Total potential subproblems: 25631
# Total visited nodes: 25611
# Average branching factor (potential): 1.3
# Average branching factor (actual): 1.3
# Result(found=true, solution=available)