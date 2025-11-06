abstract type AbstractBenchmarkProblem end
abstract type AbstractProblemConfig end
abstract type AbstractInstance end
abstract type AbstractSolver end

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
    satisfiable_when_high::Bool
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
        new(false, csat_path, yosys_path, true)
    end
end

struct KissatSolver <: AbstractSolver
    warmup::Bool
    kissat_path::String
    yosys_path::String
    abc_path::String
    satisfiable_when_high::Bool
    function KissatSolver(;kissat_path=nothing, yosys_path=nothing, abc_path=nothing)
        if isnothing(kissat_path)
            kissat_path = try
                kissat_path = strip(read(`which kissat`, String))
            catch
                error("Kissat not found in PATH, and kissat_path is not provided")
            end
        else
            !isfile(kissat_path) && error("File $kissat_path for Kissat does not exist")
        end
        new(true, kissat_path, yosys_path, abc_path, false)
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