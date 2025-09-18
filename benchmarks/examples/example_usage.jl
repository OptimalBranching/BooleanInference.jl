#!/usr/bin/env julia

# Example usage of the new multiple dispatch benchmark system

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks

println("🚀 Multiple Dispatch Benchmark System Example")
println("=" ^ 50)

# Example 1: Generate datasets for different problem sizes
println("\n📊 Generating datasets...")
configs = [
    FactoringConfig(10, 10),
    FactoringConfig(12, 12),
    FactoringConfig(14, 14)
]

generate_datasets(FactoringProblem; 
                  configs=configs, 
                  per_config=20, 
                  include_solution=true)

# Example 2: Run performance benchmarks
println("\n⏱️  Running benchmarks...")
results = benchmark_problem(FactoringProblem; 
                           configs=configs[1:2],  # Just first two for quick demo
                           samples_per_config=3)

for result in results
    config = result["config"]
    mean_time = result["mean_time"]
    println("Config $(config.m)x$(config.n): $(round(mean_time, digits=6))s average")
end

# Example 3: Run complete benchmark suite
println("\n🎯 Running full benchmark suite...")
full_results = run_full_benchmark(FactoringProblem; 
                                 dataset_per_config=10, 
                                 benchmark_samples=2)

println("\n✅ All examples completed successfully!")
println("\nTo add new problem types, simply:")
println("1. Define a new struct inheriting from AbstractBenchmarkProblem")
println("2. Define a config struct inheriting from AbstractProblemConfig") 
println("3. Implement the 5 interface methods")
println("4. Use the same generic functions!")

# Commented example of how to add a new problem type:
"""
# Example: Adding SAT Solving Problem
struct SATSolvingProblem <: AbstractBenchmarkProblem end

struct SATConfig <: AbstractProblemConfig
    num_vars::Int
    num_clauses::Int
end

function generate_instance(::Type{SATSolvingProblem}, config::SATConfig; 
                          rng=Random.GLOBAL_RNG, include_solution=false)
    # Generate random SAT instance
end

function solve_instance(::Type{SATSolvingProblem}, instance)
    # Solve the SAT instance
end

function problem_id(::Type{SATSolvingProblem}, config::SATConfig, instance_data)
    # Generate unique ID
end

function default_configs(::Type{SATSolvingProblem})
    return [SATConfig(20, 60), SATConfig(50, 150)]
end

function filename_pattern(::Type{SATSolvingProblem}, config::SATConfig)
    return "sat_\$(config.num_vars)vars_\$(config.num_clauses)clauses.jsonl"
end

# Then use it the same way:
generate_datasets(SATSolvingProblem)
benchmark_problem(SATSolvingProblem)
run_full_benchmark(SATSolvingProblem)
"""
