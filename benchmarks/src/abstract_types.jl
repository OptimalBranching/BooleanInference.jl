abstract type AbstractBenchmarkProblem end
abstract type AbstractProblemConfig end
abstract type AbstractInstance end
abstract type AbstractSolver end

# CNF-based SAT solvers share common characteristics
abstract type CNFSolver <: AbstractSolver end

struct BooleanInferenceSolver <: AbstractSolver 
    warmup::Bool
    bsconfig::BranchingStrategy
    reducer::AbstractReducer
    show_stats::Bool
    function BooleanInferenceSolver(;warmup=true, bsconfig=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MinGammaSelector(1,2, TNContractionSolver(), OptimalBranchingCore.GreedyMerge()),
        measure=NumUnfixedVars()
    ), reducer=NoReducer(), show_stats=false)
        new(warmup, bsconfig, reducer, show_stats)
    end
end

struct IPSolver <: AbstractSolver 
    warmup::Bool
    optimizer::Any
    env::Any
    verify::Bool
    function IPSolver(optimizer=Gurobi.Optimizer, env=nothing)
        new(true, optimizer, env, true)
    end
end

struct XSATSolver <: AbstractSolver
    warmup::Bool
    csat_path::String
    yosys_path::String
    verify::Bool
    timeout::Real
    function XSATSolver(;csat_path=joinpath(dirname(@__DIR__), "artifacts", "bin", "csat"), yosys_path=nothing, timeout=600.0)
        !isfile(csat_path) && error("File $csat_path for X-SAT solver does not exist")
        # check if yosys is installed by homebrew or apt

        if isnothing(yosys_path)
            yosys_path = try
                yosys_path = strip(read(`which yosys`, String))
            catch
                error("Yosys not found in PATH, and yosys_path is not provided")
            end
        else
            !isfile(yosys_path) && error("File $yosys_path for Yosys does not exist")
        end
        new(false, csat_path, yosys_path, true, timeout)
    end
end


struct KissatSolver <: CNFSolver
    warmup::Bool
    kissat_path::String
    abc_path::Union{String, Nothing}
    verify::Bool
    timeout::Real
    function KissatSolver(;kissat_path=nothing, abc_path=joinpath(dirname(@__DIR__), "artifacts", "bin", "abc"), timeout=600.0)
        kissat_path = isnothing(kissat_path) ? 
            find_executable_in_path("kissat", "Kissat") : 
            validate_executable_path(kissat_path, "Kissat")
        abc_path = validate_executable_path(abc_path, "ABC")
        new(false, kissat_path, abc_path, false, timeout)  # CNF solvers typically don't need warmup
    end
end

struct MinisatSolver <: CNFSolver
    warmup::Bool
    minisat_path::String
    abc_path::Union{String, Nothing}
    verify::Bool
    timeout::Real
    function MinisatSolver(;minisat_path=nothing, abc_path=joinpath(dirname(@__DIR__), "artifacts", "bin", "abc"), timeout=600.0)
        minisat_path = isnothing(minisat_path) ? 
            find_executable_in_path("minisat", "MiniSAT") : 
            validate_executable_path(minisat_path, "MiniSAT")
        abc_path = validate_executable_path(abc_path, "ABC")
        new(false, minisat_path, abc_path, false, timeout)
    end
end



# ----------------------------------------
# Core Interface (must be implemented)
# ----------------------------------------
function solve_instance end
function verify_solution end
function read_instances end  # Read instances from a dataset file/directory
function available_solvers end
function default_solver end

# Default fallback for solve_instance
function solve_instance(problem_type::Type{<:AbstractBenchmarkProblem}, instance)
    solve_instance(problem_type, instance, default_solver(problem_type))
end

function solver_name(::BooleanInferenceSolver)
    return "BI"
end

function solver_name(solver::IPSolver)
    return "IP-$(string(solver.optimizer)[1:end-10])"
end

function solver_name(::XSATSolver)
    return "X-SAT"
end

function solver_name(::KissatSolver)
    return "Kissat"
end

function solver_name(::MinisatSolver)
    return "MiniSAT"
end