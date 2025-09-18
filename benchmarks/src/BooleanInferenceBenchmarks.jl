module BooleanInferenceBenchmarks

using Random
using JSON3
using BenchmarkTools
using BooleanInference

# Core utilities
include("utils.jl")

# Abstract types and interfaces
include("abstract_types.jl")

# Generic benchmark framework
include("generic_benchmark.jl")

# Problem implementations
include("factoring_problem.jl")

# Re-export main interfaces
export AbstractBenchmarkProblem, AbstractProblemConfig
export generate_instance, solve_instance, problem_id, default_configs, filename_pattern
export generate_datasets, benchmark_problem, run_full_benchmark
export FactoringProblem, FactoringConfig

end # module