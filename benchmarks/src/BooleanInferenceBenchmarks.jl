"""
    BooleanInferenceBenchmarks

Benchmarking suite for BooleanInference.jl.

# Quick Start
```julia
using BooleanInferenceBenchmarks

result = solve("circuit.v")              # Solve a circuit
result = factor(143; m=4, n=4)           # Factor a number
res = benchmark("data/circuits")         # Benchmark directory
```
"""
module BooleanInferenceBenchmarks

# Dependencies
using Random
using Primes
using JuMP, HiGHS, Gurobi
using JuMP: MOI
using Statistics: mean, median
using BooleanInference
using BooleanInference: Circuit, Assignment, BooleanExpr, circuit_to_cnf
using ProblemReductions
using ProblemReductions: Factoring, CircuitSAT, reduceto
using ProblemReductions: BoolVar, CNFClause, CNF, Satisfiability
using OptimalBranchingCore

# CircuitIO module (keep separate - it's self-contained)
include("circuitIO/circuitIO.jl")
using .CircuitIO

# Core files (simplified structure)
include("types.jl")      # All types + Solvers module
include("problems.jl")   # Problem loading
include("solvers.jl")    # solve_instance implementations
include("api.jl")        # High-level API

# ============================================================================
# Exports
# ============================================================================

# New API (recommended)
export SolveStatus, SAT, UNSAT, TIMEOUT, UNKNOWN, ERROR
export SolveResult, is_sat, is_unsat
export Solvers
export load, load_dir, solve, factor, factor_batch, benchmark

# Types
export AbstractBenchmarkProblem, AbstractProblemConfig, AbstractInstance, AbstractSolver
export FactoringProblem, FactoringConfig, FactoringInstance
export CircuitSATProblem, CircuitSATConfig, CircuitSATInstance
export CNFSATProblem, CNFSATConfig, CNFSATInstance

# Solvers
export BooleanInferenceSolver, FactoringBenchmarkSolver, IPSolver, XSATSolver
export CNFSolver, KissatSolver, MinisatSolver, CNFSolverResult, CnCStats, CnCResult

# Legacy (backward compatibility)
export solve_instance, default_solver, solver_name
export read_instances, load_circuit_instance
export discover_circuit_files, discover_cnf_files
export parse_cnf_file, cnf_instantiation
export generate_factoring_datasets
export resolve_data_dir, resolve_results_dir
export run_cnf_solver

# CNF utilities
export write_cnf_dimacs, circuit_to_cnf_dimacs

end