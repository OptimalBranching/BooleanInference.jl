module BooleanInferenceBenchmarks

using Random
using JSON3
using BenchmarkTools
using BooleanInference
using JuMP, HiGHS
using ProblemReductions
using Statistics: mean, median, std, quantile
using Dates: now
using SHA: bytes2hex, sha256

include("utils.jl")
include("abstract_types.jl")
include("dataset.jl")
include("benchmark.jl")
include("formatting.jl")
include("comparison.jl")
include("factoring/types.jl")
include("factoring/generators.jl")
include("factoring/solvers.jl")
include("factoring/ip_solver.jl")
include("factoring/interface.jl")
include("aag.jl")

export AbstractBenchmarkProblem, AbstractProblemConfig, AbstractSolver
export generate_instance, solve_instance, problem_id, default_configs, filename_pattern
export available_solvers, default_solver, solver_name
export generate_datasets, benchmark_problem, run_full_benchmark
export list_available_solvers, run_solver_comparison, print_solver_comparison_summary
export compare_solver_results
export FactoringProblem, FactoringConfig, BooleanInferenceSolver, IPSolver

end