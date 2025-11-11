# Example: CircuitSAT Benchmarking with Verilog and AAG files

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using BooleanInference

# # Example 1: Benchmark a single Verilog file
# println("="^60)
# println("Example 1: Benchmark Single Verilog File (c17)")
# println("="^60)

# c17_path = joinpath(@__DIR__, "..", "data", "iscas85", "c17.v")
# result = benchmark_dataset(CircuitSATProblem, c17_path)

# if result !== nothing
#     println("\nResults:")
#     println("  Instances tested: ", result["instances_tested"])
#     println("  Successful runs: ", result["successful_runs"])
#     println("  Accuracy rate: ", round(result["accuracy_rate"] * 100, digits=2), "%")
#     println("  Median time: ", round(result["median_time"], digits=6), " seconds")
# end
# println()

c3540_path = joinpath(@__DIR__, "..", "data", "aig", "non-arithmetic", "c3540.aag")
result = benchmark_dataset(CircuitSATProblem, c3540_path)

if result !== nothing
    println("\nResults:")
    println("  Instances tested: ", result["instances_tested"])
    println("  Successful runs: ", result["successful_runs"])
    println("  Accuracy rate: ", round(result["accuracy_rate"] * 100, digits=2), "%")
    println("  Median time: ", round(result["median_time"], digits=6), " seconds")
end
println()

# Example 2: Benchmark ISCAS85 directory (all Verilog files)
println("="^60)
println("Example 2: Benchmark ISCAS85 Dataset")
println("="^60)

iscas85_dir = joinpath(@__DIR__, "..", "data", "iscas85")
result = benchmark_dataset(CircuitSATProblem, iscas85_dir)

if result !== nothing
    println("\nResults:")
    println("  Instances tested: ", result["instances_tested"])
    println("  Successful runs: ", result["successful_runs"])
    println("  Accuracy rate: ", round(result["accuracy_rate"] * 100, digits=2), "%")
    println("  Median time: ", round(result["median_time"], digits=6), " seconds")
end
println()

# Example 3: Benchmark AAG files (if available)
println("="^60)
println("Example 3: Benchmark AAG Dataset")
println("="^60)

aag_dir = joinpath(@__DIR__, "..", "data", "aig", "non-arithmetic")
if isdir(aag_dir)
    result = benchmark_dataset(CircuitSATProblem, aag_dir)
    
    if result !== nothing
        println("\nResults:")
        println("  Instances tested: ", result["instances_tested"])
        println("  Successful runs: ", result["successful_runs"])
        println("  Accuracy rate: ", round(result["accuracy_rate"] * 100, digits=2), "%")
        println("  Median time: ", round(result["median_time"], digits=6), " seconds")
    end
else
    println("AAG directory not found: $aag_dir")
end
println()

# # Example 4: Discover available circuits
# println("="^60)
# println("Example 4: Discover Available Circuits")
# println("="^60)

# verilog_files = discover_circuit_files(iscas85_dir; format=:verilog)
# println("Found $(length(verilog_files)) Verilog circuits:")
# for (i, file) in enumerate(verilog_files)
#     println("  $i. ", basename(file))
# end

# if isdir(aag_dir)
#     aag_files = discover_circuit_files(aag_dir; format=:aag)
#     println("\nFound $(length(aag_files)) AAG circuits")
# end
# println()

println("="^60)
println("Examples completed!")
println("="^60)

