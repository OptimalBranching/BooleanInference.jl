"""
Example script showing how to save and load benchmark results.

This demonstrates the new result I/O functionality with deterministic file naming.
"""

using BooleanInferenceBenchmarks

# Define result directory
result_dir = resolve_data_dir("factoring", "results")
@info "Results will be saved to: $result_dir"

# Example 1: Run benchmark and save results
println("\n" * "="^70)
println("Example 1: Running benchmark and saving results")
println("="^70)

dataset_path = resolve_data_dir("factoring", "numbers_8x8.txt")

# Create a custom solver configuration
solver = BooleanInferenceSolver(
    bsconfig=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MinGammaSelector(1, 2, TNContractionSolver(), OptimalBranchingCore.GreedyMerge()),
        measure=NumUnfixedVars()
    )
)

# Run benchmark with result saving
times, branches, result_path = benchmark_dataset(
    FactoringProblem,
    dataset_path,
    solver=solver,
    verify=true,
    save_result=result_dir  # This saves the result to a JSON file
)

println("\nResult saved to: $result_path")

# Example 2: Load and display saved results
println("\n" * "="^70)
println("Example 2: Loading and displaying saved results")
println("="^70)

if !isnothing(result_path) && isfile(result_path)
    loaded_result = load_benchmark_result(result_path)
    print_result_summary(loaded_result)
    
    # Access individual fields
    println("\nAccessing individual result fields:")
    println("Mean time: $(mean(loaded_result.times))s")
    println("Total branches: $(sum(loaded_result.branches))")
end

# Example 3: Check if result already exists
println("\n" * "="^70)
println("Example 3: Finding existing results")
println("="^70)

# Get solver configuration as dictionary
config_dict = solver_config_dict(solver)
existing_file = find_result_file(
    FactoringProblem,
    dataset_path,
    "BI",
    config_dict,
    result_dir
)

if !isnothing(existing_file)
    println("Found existing result file: $existing_file")
    # You could load it and skip re-running the benchmark
else
    println("No existing result found - would need to run benchmark")
end

# Example 4: Compare multiple solver results
println("\n" * "="^70)
println("Example 4: Comparing different solvers")
println("="^70)

# Run with different solver configurations
solvers_to_compare = [
    ("MinGamma", BooleanInferenceSolver(
        bsconfig=BranchingStrategy(
            selector=MinGammaSelector(1, 2, TNContractionSolver(), OptimalBranchingCore.GreedyMerge())
        )
    )),
    ("MostOccurrence", BooleanInferenceSolver(
        bsconfig=BranchingStrategy(
            selector=LeastOccurrenceSelector(1, 0, TNContractionSolver(), OptimalBranchingCore.GreedyMerge())
        )
    ))
]

results = []
for (name, solver) in solvers_to_compare
    println("\nRunning with $name selector...")
    times, branches, path = benchmark_dataset(
        FactoringProblem,
        dataset_path,
        solver=solver,
        verify=true,
        save_result=result_dir
    )
    
    if !isnothing(path)
        push!(results, load_benchmark_result(path))
    end
end

# Compare results
if length(results) >= 2
    println("\n" * "="^70)
    println("Comparison Summary")
    println("="^70)
    
    for result in results
        println("\n$(result.solver_name) - $(result.solver_config["selector"]):")
        println("  Mean time: $(round(mean(result.times), digits=4))s")
        println("  Mean branches: $(round(mean(result.branches), digits=2))")
    end
end

println("\n" * "="^70)
println("All results saved in: $result_dir")
println("="^70)

