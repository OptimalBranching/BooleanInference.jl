#!/usr/bin/env julia

# Standalone benchmark runner script using multiple dispatch architecture
# Usage: julia --project=benchmark benchmark/scripts/run_benchmarks.jl

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks

function main()
	println("🚀 Running BooleanInference benchmarks with multiple dispatch...")
	
	# Run factoring benchmarks using new system
	println("\n📊 Running Factoring Problem benchmarks...")
	results = run_full_benchmark(FactoringProblem; 
	                            dataset_per_config=50, 
	                            benchmark_samples=3)

	# Print summary
	println("\n📈 Benchmark Results:")
	for result in results
		config = result["config"]
		mean_t = result["mean_time"]
		min_t = result["min_time"]
		println("  $(config.m)×$(config.n): $(round(mean_t, digits=4))s avg, $(round(min_t, digits=4))s min")
	end

	# You can easily add more problem types here:
	# results2 = run_full_benchmark(AnotherProblem)

	println("\n✅ All benchmarks completed!")
	println("💡 Check benchmark/data/ for generated datasets")
end

if abspath(PROGRAM_FILE) == @__FILE__
	main()
end
