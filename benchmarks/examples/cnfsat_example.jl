using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using ProblemReductions
using BooleanInference
using BooleanInference.OptimalBranchingCore

result_dir = resolve_results_dir("CNFSAT")

for n in [100, 200, 300]
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

        # result = benchmark_dataset(
        #     CNFSATProblem,
        #     dataset_path;
        #     solver=KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0, quiet=false),
        #     verify=false,
        #     save_result=result_dir
        # )
end
end

# test_file = joinpath(dataset_path, "3sat10.cnf")
# test_instance = parse_cnf_file(test_file)
# result = solve_instance(CNFSATProblem, test_instance, BooleanInferenceSolver(;bsconfig, show_stats=true))
# result = solve_instance(CNFSATProblem, test_instance, KissatSolver(kissat_path="/opt/homebrew/bin/kissat", timeout=300.0, quiet=false))