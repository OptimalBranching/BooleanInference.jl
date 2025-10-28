using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks

# ----------------------------------------
# Example: CircuitSAT benchmark
# ----------------------------------------
# No need to generate datasets - just point to existing .aag files

println("=" ^80)
println("Running CircuitSAT Benchmark")
println("=" ^80)

# Option 1: Point to a directory with .aag files
aig_dir = joinpath(@__DIR__, "..", "data", "aig", "arithmetic")

if isdir(aig_dir)
    result = benchmark_dataset(CircuitSATProblem, aig_dir; 
                              solver=BooleanInferenceSolver())
    
    if !isnothing(result)
        println("\nResults:")
        println("  Dataset: $(result["dataset_path"])")
        println("  Instances tested: $(result["instances_tested"])")
        println("  Accuracy: $(round(result["accuracy_rate"]*100, digits=1))%")
        println("  Median time: $(result["median_time"]) seconds")
    end
else
    println("Directory not found: $aig_dir")
    println("Please ensure you have .aag files in that directory")
end

# Option 2: Create a file list
# Create a text file with paths to .aag files, one per line
# Then: result = benchmark_dataset(CircuitSATProblem, "my_circuits.txt")

