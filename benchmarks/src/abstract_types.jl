abstract type AbstractBenchmarkProblem end
abstract type AbstractProblemConfig end
abstract type AbstractInstance end
abstract type AbstractSolver end

# CNF-based SAT solvers share common characteristics
abstract type CNFSolver <: AbstractSolver end

@kwdef struct BooleanInferenceSolver <: AbstractSolver 
    warmup::Bool = true
end

struct IPSolver <: AbstractSolver 
    warmup::Bool
    optimizer::Any
    env::Any
    function IPSolver(optimizer=Gurobi.Optimizer, env=nothing)
        new(true, optimizer, env)
    end
end

struct XSATSolver <: AbstractSolver
    warmup::Bool
    csat_path::String
    yosys_path::String
    function XSATSolver(;csat_path=joinpath(dirname(@__DIR__), "artifacts", "bin", "csat"), yosys_path=nothing)
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
        new(false, csat_path, yosys_path)
    end
end


struct KissatSolver <: CNFSolver
    warmup::Bool
    kissat_path::String
    abc_path::Union{String, Nothing}
    function KissatSolver(;kissat_path=nothing, abc_path=nothing)
        kissat_path = isnothing(kissat_path) ? 
            find_executable_in_path("kissat", "Kissat") : 
            validate_executable_path(kissat_path, "Kissat")
        abc_path = validate_executable_path(abc_path, "ABC")
        new(false, kissat_path, abc_path)  # CNF solvers typically don't need warmup
    end
end

struct MinisatSolver <: CNFSolver
    warmup::Bool
    minisat_path::String
    abc_path::Union{String, Nothing}
    function MinisatSolver(;minisat_path=nothing, abc_path=nothing)
        minisat_path = isnothing(minisat_path) ? 
            find_executable_in_path("minisat", "MiniSAT") : 
            validate_executable_path(minisat_path, "MiniSAT")
        abc_path = validate_executable_path(abc_path, "ABC")
        new(false, minisat_path, abc_path)
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