using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using ProblemReductions
using BooleanInference
using BooleanInference.OptimalBranchingCore

result_dir = resolve_results_dir("CNFSAT")

for n in [100]
    for r in [350, 380, 400, 420, 430, 450]
    dataset_path = joinpath(@__DIR__, "..", "data", "3CNF", "random", "n=$(n)", "$(n)-$(r)")

    for i in 1:5
        bsconfig = BranchingStrategy(
            table_solver=TNContractionSolver(),
            # selector=MinGammaSelector(1,2,TNContractionSolver(), GreedyMerge()),
            selector=MostOccurrenceSelector(3,i),
            measure=NumHardTensors(),
            set_cover_solver=GreedyMerge()
        )

        result = benchmark_dataset(
            CNFSATProblem,
            dataset_path;
            solver=BooleanInferenceSolver(;bsconfig),
            verify=false,
            save_result=result_dir
        )
    end

        result = benchmark_dataset(
            CNFSATProblem,
            dataset_path;
            solver=MinisatSolver(minisat_path="/opt/homebrew/bin/minisat", timeout=300.0, quiet=false),
            verify=false,
            save_result=result_dir
        )
end
end

bsconfig = BranchingStrategy(
            table_solver=TNContractionSolver(),
            # selector=MinGammaSelector(1,2),
            selector=MostOccurrenceSelector(3,2),
            measure=NumUnfixedTensors(),
            set_cover_solver=GreedyMerge()
        )

test_file = "/Users/xiweipan/Codes/BooleanInference/benchmarks/data/3CNF/random/n=150/150-630/3sat_n150_r630_1.cnf"
test_instance = parse_cnf_file(test_file)
solver = Solvers.BI(selector=MinGammaSelector(3, 3, 0), set_cover_solver=GreedyMerge(), show_stats=true, reducer=NoReducer())
solver = Solvers.BI(selector=MostOccurrenceSelector(3, 2), set_cover_solver=GreedyMerge(), show_stats=true, reducer=NoReducer())
result = solve_instance(CNFSATProblem, test_instance, solver)

# result = solve_instance(CNFSATProblem, test_instance, KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0, quiet=false))