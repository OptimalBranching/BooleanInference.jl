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
using ProblemReductions: BoolVar, CNFClause, CNF, Satisfiability
using OptimalBranchingCore

include("abstract_types.jl")
include("utils.jl")
include("result_io.jl")
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

# CircuitSAT problem
include("circuitSAT/types.jl")
include("circuitSAT/interface.jl")
include("circuitSAT/dataset.jl")
include("circuitSAT/solvers.jl")

# CNFSAT problem
include("CNFSAT/types.jl")
include("CNFSAT/parser.jl")
include("CNFSAT/dataset.jl")
include("CNFSAT/interface.jl")
include("CNFSAT/solvers.jl")

export AbstractBenchmarkProblem, AbstractProblemConfig, AbstractInstance, AbstractSolver
export solve_instance, verify_solution, read_instances, generate_instance
export available_solvers, default_solver, solver_name, problem_id
export benchmark_dataset, run_solver_comparison
export list_available_solvers, print_solver_comparison_summary, compare_solver_results
export BenchmarkResult, save_benchmark_result, load_benchmark_result
export print_result_summary, find_result_file, solver_config_dict
export resolve_results_dir
export FactoringProblem, FactoringConfig, FactoringInstance, generate_factoring_datasets
export CircuitSATProblem, CircuitSATConfig, CircuitSATInstance
export load_circuit_instance, load_verilog_dataset, load_aag_dataset
export load_circuit_datasets, discover_circuit_files, create_circuitsat_configs
export is_satisfiable
export BooleanInferenceSolver, IPSolver, XSATSolver
export CNFSolver, KissatSolver, MinisatSolver
export CNFSolverResult, run_cnf_solver
export CNFSATProblem, CNFSATConfig, CNFSATInstance
export parse_cnf_file, cnf_instantiation
export load_cnf_dataset, load_cnf_datasets, discover_cnf_files, create_cnfsat_configs
export load_cnf_instance, is_cnf_satisfiable
export resolve_data_dir

end