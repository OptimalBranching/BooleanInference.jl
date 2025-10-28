abstract type AbstractBenchmarkProblem end
abstract type AbstractProblemConfig end
abstract type AbstractInstance end
abstract type AbstractSolver end

struct BooleanInferenceSolver <: AbstractSolver end

struct IPSolver <: AbstractSolver 
    optimizer::Any
    env::Any
    function IPSolver(optimizer=Gurobi.Optimizer, env=nothing)
        new(optimizer, env)
    end
end

struct XSATSolver <: AbstractSolver
    path::String
    function XSATSolver(path::String=joinpath(dirname(@__DIR__), "artifacts", "bin", "csat"))
        !isfile(path) && error("File $path for X-SAT solver does not exist")
        new(path)
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