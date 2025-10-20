module BooleanInferenceBenchmarks

using Random
using JSON3
using BenchmarkTools
using BooleanInference
using JuMP
using ProblemReductions
using Statistics: mean, median, std, quantile
using Dates: now
using SHA: bytes2hex, sha256


# Core utilities
include("utils.jl")

# Abstract types and interfaces
include("abstract_types.jl")

# Generic benchmark framework
include("generic_benchmark.jl")

# Problem implementations
include("factoring/factoring_problem.jl")
include("factoring/factor_IP.jl")

# Re-export main interfaces
export AbstractBenchmarkProblem, AbstractProblemConfig, AbstractSolver
export generate_instance, solve_instance, problem_id, default_configs, filename_pattern
export available_solvers, default_solver, solver_name
export generate_datasets, benchmark_problem, run_full_benchmark, benchmark_backend
export create_configs_from_tuples
export list_available_solvers, run_solver_comparison
export FactoringProblem, FactoringConfig, BooleanInferenceSolver, IPSolver
export print_solver_comparison_summary, save_solver_comparison

end # module