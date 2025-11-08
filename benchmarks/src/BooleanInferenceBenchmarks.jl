module BooleanInferenceBenchmarks

using Random
using JSON3
using Primes
using Dates: now
using BenchmarkTools
using BooleanInference
using JuMP, HiGHS, Gurobi
using Statistics: mean, median
using SHA: bytes2hex, sha256, sha1
using ProblemReductions
using ProblemReductions: Factoring, CircuitSAT, reduceto, constraints, objectives, AbstractProblem, Symbol

include("abstract_types.jl")
include("utils.jl")
include("benchmark.jl")
include("formatting.jl")
include("comparison.jl")

# CircuitIO
include("circuitIO/circuitIO.jl")
using .CircuitIO

include("solver/solver_ip.jl")
include("solver/solver_xsat.jl")
include("solver/solver_cnfsat.jl")

# Factoring problem
include("factoring/types.jl")
include("factoring/interface.jl")
include("factoring/generators.jl")
include("factoring/solvers.jl")
include("factoring/dataset.jl")


export AbstractBenchmarkProblem, AbstractProblemConfig, AbstractInstance, AbstractSolver
export solve_instance, verify_solution, read_instances
export available_solvers, default_solver, solver_name
export benchmark_dataset, run_solver_comparison
export list_available_solvers, print_solver_comparison_summary, compare_solver_results
export FactoringProblem, FactoringConfig, FactoringInstance, generate_factoring_datasets
export CircuitSATProblem, CircuitSATConfig, CircuitSATInstance
export BooleanInferenceSolver, IPSolver, XSATSolver
export CNFSolver, KissatSolver, MinisatSolver
export CNFSolverResult, run_cnf_solver

end