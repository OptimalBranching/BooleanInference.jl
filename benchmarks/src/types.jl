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
- `branches::Int`: Branch/decision count
- `solver::String`: Solver name
"""
struct SolveResult
    status::SolveStatus
    solution::Any
    time::Float64
    branches::Int
    solver::String
end

Base.show(io::IO, r::SolveResult) = print(io, "SolveResult($(r.status), time=$(round(r.time, digits=4))s, branches=$(r.branches))")
is_sat(r::SolveResult) = r.status == SAT
is_unsat(r::SolveResult) = r.status == UNSAT

# ============================================================================
# Solver Types
# ============================================================================

struct BooleanInferenceSolver <: AbstractSolver
    bsconfig::BranchingStrategy
    reducer::Any
    show_stats::Bool
    use_cdcl::Bool
    conflict_limit::Int
    max_clause_len::Int
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

struct CNFSolverResult
    status::Symbol  # :sat | :unsat | :unknown
    model::Union{Nothing,Dict{Int,Bool}}
    raw::String
    decisions::Union{Nothing,Int}
end

# ============================================================================
# Solver Factory (Solvers module)
# ============================================================================

module Solvers
using ..BooleanInferenceBenchmarks: BooleanInferenceSolver, IPSolver, XSATSolver
using ..BooleanInferenceBenchmarks: KissatSolver, MinisatSolver, MarchCuSolver
using BooleanInference: BranchingStrategy, TNContractionSolver, GreedyMerge, NaiveBranch
using BooleanInference: MostOccurrenceSelector, NumUnfixedVars, NumHardTensors, NoReducer
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
    measure::AbstractMeasure=NumUnfixedVars(),
    set_cover_solver::AbstractSetCoverSolver=GreedyMerge(),
    reducer::AbstractReducer=NoReducer(),
    show_stats::Bool=false,
    use_cdcl::Bool=false,
    conflict_limit::Int=40000,
    max_clause_len::Int=5
)
    bsconfig = BranchingStrategy(; table_solver, selector, measure, set_cover_solver)
    @show bsconfig
    BooleanInferenceSolver(bsconfig, reducer, show_stats, use_cdcl, conflict_limit, max_clause_len)
end

function Kissat(; timeout=600.0, quiet=true)
    path = try
        strip(read(`which kissat`, String))
    catch
        error("Kissat not found")
    end
    abc = joinpath(dirname(@__DIR__), "artifacts", "bin", "abc")
    KissatSolver(path, isfile(abc) ? abc : nothing, Float64(timeout), quiet)
end

function Minisat(; timeout=600.0, quiet=true)
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

export BI, Kissat, Minisat, Gurobi, HiGHS, XSAT, MarchCu
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
solver_name(s::IPSolver) = "IP-$(string(s.optimizer)[1:end-10])"
solver_name(::XSATSolver) = "X-SAT"
solver_name(::KissatSolver) = "Kissat"
solver_name(::MinisatSolver) = "MiniSAT"

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
