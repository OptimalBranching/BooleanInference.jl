# ============================================================================
# types.jl - All type definitions and solver constructors
# ============================================================================

using BooleanInference: BranchingStrategy, TNContractionSolver, GreedyMerge
using BooleanInference: MostOccurrenceSelector, NumUnfixedVars, NoReducer

# ============================================================================
# Abstract Types
# ============================================================================

abstract type AbstractBenchmarkProblem end
abstract type AbstractProblemConfig end
abstract type AbstractInstance end
abstract type AbstractSolver end

# ============================================================================
# Status and Result
# ============================================================================

@enum SolveStatus SAT UNSAT TIMEOUT UNKNOWN ERROR

"""
    SolveResult

Unified result type for all problems.

# Fields
- `status::SolveStatus`: SAT, UNSAT, TIMEOUT, UNKNOWN, or ERROR
- `solution::Any`: Problem-specific solution
- `time::Float64`: Solve time (seconds)
- `branches::Int`: Branch/decision count (γ>1 for OB-SAT, decisions for CDCL)
- `gamma_one::Int`: γ=1 reduction count (OB-SAT only, 0 for CDCL)
- `avg_vars_per_branch::Float64`: Average variables fixed per branch (OB-SAT only, 0.0 for CDCL)
- `gamma_one_vars::Int`: Total variables fixed by γ=1 reductions (OB-SAT only)
- `branch_vars::Int`: Total variables fixed by γ>1 branches (OB-SAT only)
- `solver::String`: Solver name
"""
struct SolveResult
    status::SolveStatus
    solution::Any
    time::Float64
    branches::Int
    conflicts::Int              # unsat_leaves (BI) or conflicts (CDCL)
    gamma_one::Int
    avg_vars_per_branch::Float64
    gamma_one_vars::Int
    branch_vars::Int
    solver::String
end

# Constructor with defaults for backward compatibility
SolveResult(status, solution, time, branches, solver::String) = SolveResult(status, solution, time, branches, 0, 0, 0.0, 0, 0, solver)
SolveResult(status, solution, time, branches, conflicts::Int, solver::String) = SolveResult(status, solution, time, branches, conflicts, 0, 0.0, 0, 0, solver)
SolveResult(status, solution, time, branches, conflicts::Int, gamma_one::Int, solver::String) = SolveResult(status, solution, time, branches, conflicts, gamma_one, 0.0, 0, 0, solver)
SolveResult(status, solution, time, branches, conflicts::Int, gamma_one::Int, avg_vars::Float64, solver::String) = SolveResult(status, solution, time, branches, conflicts, gamma_one, avg_vars, 0, 0, solver)

Base.show(io::IO, r::SolveResult) = print(io, "SolveResult($(r.status), time=$(round(r.time, digits=4))s, branches=$(r.branches), γ=1_vars=$(r.gamma_one_vars), branch_vars=$(r.branch_vars))")
is_sat(r::SolveResult) = r.status == SAT
is_unsat(r::SolveResult) = r.status == UNSAT

# ============================================================================
# Solver Types
# ============================================================================

struct BooleanInferenceSolver <: AbstractSolver
    bsconfig::BranchingStrategy
    reducer::Any
    show_stats::Bool
    cdcl_cutoff::Float64  # Cube and Conquer: switch to CDCL when unfixed_ratio <= this
end

"""
    FactoringBenchmarkSolver

Solver that uses pre-computed FactoringBenchmark for efficient batch solving.
The benchmark pre-computes clustering and N-independent contractions once,
then reuses them across multiple factoring instances with different N values.
"""
struct FactoringBenchmarkSolver <: AbstractSolver
    benchmark::Any  # FactoringBenchmark from BooleanInference
    show_stats::Bool
    cdcl_cutoff::Float64
end

struct IPSolver <: AbstractSolver
    optimizer::Any
    env::Any
end

struct XSATSolver <: AbstractSolver
    csat_path::String
    yosys_path::String
    timeout::Float64
end

abstract type CNFSolver <: AbstractSolver end

struct KissatSolver <: CNFSolver
    kissat_path::String
    abc_path::Union{String,Nothing}
    timeout::Float64
    quiet::Bool
end

struct MinisatSolver <: CNFSolver
    minisat_path::String
    abc_path::Union{String,Nothing}
    timeout::Float64
    quiet::Bool
end

struct MarchCuSolver <: CNFSolver
    march_cu_path::String
    kissat_path::String
    abc_path::Union{String,Nothing}
    timeout::Float64
end

"""
    CnCSolver

Cube and Conquer solver that uses march_cu to generate cubes, 
then kissat to solve each cube in parallel/sequentially.

Cutoff parameters control when to stop splitting:
- `cutoff_depth`: Static depth cutoff (-d option)
- `cutoff_nvars`: Static variable cutoff (-n option)  
- `down_exponent`: Dynamic cutoff exponent (-e option)
- `down_fraction`: Dynamic cutoff fraction (-f option)
- `max_cubes`: Maximum number of cubes (-l option)
"""
struct CnCSolver <: CNFSolver
    march_cu_path::String
    kissat_path::String
    abc_path::Union{String,Nothing}
    timeout::Float64
    cubes_file::Union{String,Nothing}  # Optional: path to save cubes
    # Cutoff parameters
    cutoff_depth::Int      # -d: static depth cutoff (0 = dynamic)
    cutoff_nvars::Int      # -n: static variable cutoff (0 = dynamic)
    down_exponent::Float64 # -e: down exponent for dynamic cutoff (default 0.30)
    down_fraction::Float64 # -f: down fraction for dynamic cutoff (default 0.02)
    max_cubes::Int         # -l: max number of cubes (0 = no limit)
end

"""
    CryptoMiniSatSolver

CryptoMiniSat SAT solver - a CDCL solver with Gaussian elimination.
"""
struct CryptoMiniSatSolver <: CNFSolver
    cryptominisat_path::String
    abc_path::Union{String,Nothing}
    timeout::Float64
    threads::Int
    quiet::Bool
end

struct CNFSolverResult
    status::Symbol  # :sat | :unsat | :unknown
    model::Union{Nothing,Dict{Int,Bool}}
    raw::String
    decisions::Union{Nothing,Int}
    conflicts::Union{Nothing,Int}
end

function Base.show(io::IO, r::CNFSolverResult)
    dec_str = isnothing(r.decisions) ? "?" : string(r.decisions)
    conf_str = isnothing(r.conflicts) ? "?" : string(r.conflicts)
    print(io, "CNFSolverResult(:$(r.status), decisions=$(dec_str), conflicts=$(conf_str))")
end

"""
    CnCStats

Statistics for Cube-and-Conquer solving.

# Fields
- `num_cubes::Int`: Total number of cubes generated
- `num_refuted::Int`: Number of cubes refuted during lookahead
- `cubing_time::Float64`: Time spent generating cubes (seconds)
- `avg_cube_vars::Float64`: Average number of literals per cube
- `cubes_solved::Int`: Number of cubes solved by CDCL
- `avg_decisions::Float64`: Average CDCL decisions per cube
- `avg_conflicts::Float64`: Average CDCL conflicts per cube
- `avg_solve_time::Float64`: Average CDCL solving time per cube (seconds)
- `total_solve_time::Float64`: Total CDCL solving time (seconds)
"""
struct CnCStats
    num_cubes::Int
    num_refuted::Int
    cubing_time::Float64
    avg_cube_vars::Float64
    cubes_solved::Int
    avg_decisions::Float64
    avg_conflicts::Float64
    avg_solve_time::Float64
    total_solve_time::Float64
end

function Base.show(io::IO, s::CnCStats)
    print(io, "CnCStats(cubes=$(s.num_cubes), refuted=$(s.num_refuted), cubing=$(round(s.cubing_time, digits=2))s, " *
              "solved=$(s.cubes_solved), avg_dec=$(round(s.avg_decisions, digits=1)), " *
              "avg_conf=$(round(s.avg_conflicts, digits=1)), solve=$(round(s.total_solve_time, digits=2))s)")
end

"""
    CnCResult

Result type for Cube-and-Conquer solver.

# Fields
- `status::Symbol`: :sat | :unsat | :unknown
- `model::Union{Nothing,Dict{Int,Bool}}`: Satisfying assignment if SAT
- `stats::CnCStats`: Solving statistics
- `raw::String`: Raw solver output
- `branching_vars::Vector{Int}`: Variables selected for branching (in order of first appearance)
"""
struct CnCResult
    status::Symbol  # :sat | :unsat | :unknown
    model::Union{Nothing,Dict{Int,Bool}}
    stats::CnCStats
    raw::String
    branching_vars::Vector{Int}  # Variables selected for branching
end

function Base.show(io::IO, r::CnCResult)
    print(io, "CnCResult(:$(r.status), $(r.stats), branching_vars=$(length(r.branching_vars)))")
end

# ============================================================================
# Solver Factory (Solvers module)
# ============================================================================

module Solvers
using ..BooleanInferenceBenchmarks: BooleanInferenceSolver, FactoringBenchmarkSolver, IPSolver, XSATSolver
using ..BooleanInferenceBenchmarks: KissatSolver, MinisatSolver, MarchCuSolver, CnCSolver, CryptoMiniSatSolver
using BooleanInference: BranchingStrategy, TNContractionSolver, GreedyMerge, NaiveBranch
using BooleanInference: MostOccurrenceSelector, NumUnfixedVars, NumUnfixedTensors, NumHardTensors, NoReducer
using BooleanInference: ClusteringSelector, FactoringBenchmark
using BooleanInference: AbstractTableSolver, AbstractSetCoverSolver, AbstractMeasure
using OptimalBranchingCore: AbstractReducer
using Gurobi, HiGHS

"""
    BI(; kwargs...) -> BooleanInferenceSolver

Create BooleanInference solver with full parameter control.

# Keyword Arguments
- `table_solver`: Table solver (default: `TNContractionSolver()`)
- `selector`: Variable selector (default: `MostOccurrenceSelector(3, 6)`)
- `measure`: Branching measure (default: `NumUnfixedVars()`)
- `set_cover_solver`: Set cover solver (default: `GreedyMerge()`)
- `reducer`: Reducer (default: `NoReducer()`)
- `show_stats::Bool`: Print statistics (default: `false`)
- `use_cdcl::Bool`: Use CDCL preprocessing (default: `true` for factoring, `false` for others)
- `conflict_limit::Int`: CDCL conflict limit (default: `40000`)
- `max_clause_len::Int`: Max learned clause length (default: `5`)

# Examples
```julia
solver = Solvers.BI()  # default
solver = Solvers.BI(selector=MostOccurrenceSelector(4, 8))
solver = Solvers.BI(measure=NumHardTensors(), show_stats=true)
```
"""
function BI(;
    table_solver::AbstractTableSolver=TNContractionSolver(),
    selector=MostOccurrenceSelector(3, 4),
    measure::AbstractMeasure=NumUnfixedTensors(),
    set_cover_solver::AbstractSetCoverSolver=GreedyMerge(),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false,
    cdcl_cutoff::Float64=1.0  # Cube and Conquer: switch to CDCL when unfixed_ratio <= this
)
    bsconfig = BranchingStrategy(; table_solver, selector, measure, set_cover_solver)
    BooleanInferenceSolver(bsconfig, reducer, show_stats, cdcl_cutoff)
end

"""
    BIBenchmark(m::Int, n::Int; kwargs...) -> FactoringBenchmarkSolver

Create a FactoringBenchmark-based solver for efficient batch factoring.

Pre-computes clustering and N-independent contractions once during construction,
then reuses them across multiple factoring instances. Significantly faster than
`BI()` when solving many instances with the same (m, n) configuration.

# Arguments
- `m::Int`: Number of bits for first factor
- `n::Int`: Number of bits for second factor

# Keyword Arguments
- `max_vars::Int`: Max variables per region (default: 7)
- `min_gain::Int`: Min gain threshold for clustering (default: 2)
- `precompute::Bool`: Pre-compute all N-independent contractions (default: true)
- `show_stats::Bool`: Print statistics (default: false)
- `cdcl_cutoff::Float64`: CDCL cutoff ratio (default: 0.8)

# Example
```julia
# Create benchmark solver (one-time setup cost)
solver = Solvers.BIBenchmark(8, 8)

# Solve multiple instances efficiently
for N in [77, 143, 323, 437]
    result = factor(N; m=8, n=8, solver=solver)
    println("\$N: \$(result.solution)")
end
```
"""
function BIBenchmark(m::Int, n::Int;
    max_vars::Int=7,
    min_gain::Int=2,
    precompute::Bool=true,
    show_stats::Bool=false,
    cdcl_cutoff::Float64=0.8,
    table_solver::AbstractTableSolver=TNContractionSolver(),
    selector=MostOccurrenceSelector(3, 4),
    measure::AbstractMeasure=NumUnfixedVars(),
    set_cover_solver::AbstractSetCoverSolver=GreedyMerge(),
    reducer::AbstractReducer=NoReducer(),
)
    bsconfig = BranchingStrategy(;
        table_solver,
        selector=ClusteringSelector(max_vars=max_vars, min_gain=min_gain),
        measure,
        set_cover_solver
    )
    bench = FactoringBenchmark(n, m; bsconfig=bsconfig, precompute_contractions=precompute)
    FactoringBenchmarkSolver(bench, show_stats, cdcl_cutoff)
end

function Kissat(; timeout=600.0, quiet=false)
    path = try
        strip(read(`which kissat`, String))
    catch
        error("Kissat not found")
    end
    abc = joinpath(dirname(@__DIR__), "artifacts", "bin", "abc")
    KissatSolver(path, isfile(abc) ? abc : nothing, Float64(timeout), quiet)
end

function Minisat(; timeout=600.0, quiet=false)
    path = try
        strip(read(`which minisat`, String))
    catch
        error("Minisat not found")
    end
    abc = joinpath(dirname(@__DIR__), "artifacts", "bin", "abc")
    MinisatSolver(path, isfile(abc) ? abc : nothing, Float64(timeout), quiet)
end

Gurobi(; env=nothing) = IPSolver(Gurobi.Optimizer, env)
HiGHS() = IPSolver(HiGHS.Optimizer, nothing)

function XSAT(; timeout=600.0)
    csat = joinpath(dirname(@__DIR__), "artifacts", "bin", "csat")
    yosys = try
        strip(read(`which yosys`, String))
    catch
        error("Yosys not found")
    end
    XSATSolver(csat, yosys, Float64(timeout))
end

function MarchCu(; timeout=600.0)
    artifacts = joinpath(dirname(@__DIR__), "artifacts", "bin")
    march_cu = joinpath(artifacts, "march_cu")
    abc = joinpath(artifacts, "abc")
    kissat = try
        strip(read(`which kissat`, String))
    catch
        error("Kissat not found (needed for solving cubes)")
    end
    MarchCuSolver(march_cu, kissat, isfile(abc) ? abc : nothing, Float64(timeout))
end

"""
    CnC(; kwargs...) -> CnCSolver

Create a Cube and Conquer solver.

This is a two-stage solver:
1. march_cu generates cubes (subproblems) using look-ahead
2. kissat solves each cube using CDCL

# Keyword Arguments
- `timeout::Float64`: Maximum time for solving (default: 600.0 seconds)
- `cubes_file::String`: Optional path to save generated cubes (default: nothing)

## Cutoff Parameters (control cube generation)
- `cutoff_depth::Int`: Static depth cutoff, -d option (default: 0 = dynamic)
- `cutoff_nvars::Int`: Stop when #vars < n, -n option (default: 0 = dynamic)
- `down_exponent::Float64`: Dynamic cutoff exponent, -e option (default: 0.30)
- `down_fraction::Float64`: Dynamic cutoff fraction, -f option (default: 0.02)
- `max_cubes::Int`: Max number of cubes, -l option (default: 0 = no limit)

# Dynamic Cutoff Mechanism
The cutoff threshold δ is updated as: δ := δ * (1 - F^(d^E))
where F = down_fraction, E = down_exponent, d = depth.

# Example
```julia
# Default settings (dynamic cutoff)
solver = Solvers.CnC(timeout=300.0)

# Fixed depth cutoff: generate at most 2^10 = 1024 cubes
solver = Solvers.CnC(cutoff_depth=10)

# Fixed variable cutoff: stop when < 50 variables remain
solver = Solvers.CnC(cutoff_nvars=50)

# Limit to 1000 cubes max
solver = Solvers.CnC(max_cubes=1000)
```
"""
function CnC(;
    timeout=600.0,
    cubes_file=nothing,
    cutoff_depth::Int=0,
    cutoff_nvars::Int=0,
    down_exponent::Float64=0.30,
    down_fraction::Float64=0.02,
    max_cubes::Int=0
)
    artifacts = joinpath(dirname(@__DIR__), "artifacts", "bin")
    march_cu = joinpath(artifacts, "march_cu")
    abc = joinpath(artifacts, "abc")
    kissat = try
        strip(read(`which kissat`, String))
    catch
        error("Kissat not found (needed for solving cubes)")
    end
    CnCSolver(march_cu, kissat, isfile(abc) ? abc : nothing, Float64(timeout), cubes_file,
        cutoff_depth, cutoff_nvars, down_exponent, down_fraction, max_cubes)
end

"""
    CryptoMiniSat(; timeout=600.0, threads=1, quiet=true) -> CryptoMiniSatSolver

Create a CryptoMiniSat solver.

CryptoMiniSat is a CDCL-based SAT solver with advanced features like:
- Gaussian elimination for XOR constraints
- Multi-threading support
- SLS (Stochastic Local Search) integration

# Keyword Arguments
- `timeout::Float64`: Maximum time for solving (default: 600.0 seconds)
- `threads::Int`: Number of threads to use (default: 1)
- `quiet::Bool`: Suppress output (default: true)

# Example
```julia
solver = Solvers.CryptoMiniSat(threads=4, timeout=300.0)
result = solve(problem, solver)
```
"""
function CryptoMiniSat(; timeout=600.0, threads=1, quiet=false)
    path = "/opt/homebrew/bin/cryptominisat5"
    if !isfile(path)
        path = try
            strip(read(`which cryptominisat5`, String))
        catch
            error("CryptoMiniSat not found at /opt/homebrew/bin/cryptominisat5 or in PATH")
        end
    end
    abc = joinpath(dirname(@__DIR__), "artifacts", "bin", "abc")
    CryptoMiniSatSolver(path, isfile(abc) ? abc : nothing, Float64(timeout), threads, quiet)
end

export BI, BIBenchmark, Kissat, Minisat, Gurobi, HiGHS, XSAT, MarchCu, CnC, CryptoMiniSat
end

# ============================================================================
# Problem Types
# ============================================================================

# --- Factoring ---
struct FactoringProblem <: AbstractBenchmarkProblem end
struct FactoringConfig <: AbstractProblemConfig
    m::Int
    n::Int
end
struct FactoringInstance <: AbstractInstance
    m::Int
    n::Int
    N::BigInt
    p::Union{BigInt,Nothing}
    q::Union{BigInt,Nothing}
    FactoringInstance(m::Int, n::Int, N::Integer; p=nothing, q=nothing) =
        new(m, n, BigInt(N), isnothing(p) ? nothing : BigInt(p), isnothing(q) ? nothing : BigInt(q))
end

# --- CircuitSAT ---
struct CircuitSATProblem <: AbstractBenchmarkProblem end
struct CircuitSATConfig <: AbstractProblemConfig
    format::Symbol  # :verilog or :aag
    path::String
    CircuitSATConfig(format::Symbol, path::String) = begin
        format in (:verilog, :aag) || error("Format must be :verilog or :aag")
        new(format, path)
    end
end
struct CircuitSATInstance <: AbstractInstance
    name::String
    circuit::Circuit
    format::Symbol
    source_path::String
end

# --- CNF SAT ---
struct CNFSATProblem <: AbstractBenchmarkProblem end
struct CNFSATConfig <: AbstractProblemConfig
    path::String
end
struct CNFSATInstance <: AbstractInstance
    name::String
    num_vars::Int
    clauses::Vector{Vector{Int}}
    source_path::String
end

# ============================================================================
# Utility Functions
# ============================================================================

solver_name(::BooleanInferenceSolver) = "BI"
solver_name(::FactoringBenchmarkSolver) = "BI-Bench"
solver_name(s::IPSolver) = "IP-$(string(s.optimizer)[1:end-10])"
solver_name(::XSATSolver) = "X-SAT"
solver_name(::KissatSolver) = "Kissat"
solver_name(::MinisatSolver) = "MiniSAT"
solver_name(::MarchCuSolver) = "march_cu"
solver_name(::CnCSolver) = "CnC"
solver_name(::CryptoMiniSatSolver) = "CryptoMiniSat"

function resolve_data_dir(parts::AbstractString...)
    dir = joinpath(dirname(@__DIR__), "data", parts...)
    isdir(dir) || mkpath(dir)
    dir
end

function resolve_results_dir(problem::AbstractString)
    dir = joinpath(dirname(@__DIR__), "results", problem)
    isdir(dir) || mkpath(dir)
    dir
end
