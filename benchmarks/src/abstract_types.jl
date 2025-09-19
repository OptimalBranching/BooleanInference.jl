# Abstract types and interfaces for benchmark problems

"""
Abstract base type for all benchmark problems.
"""
abstract type AbstractBenchmarkProblem end

"""
Abstract base type for problem configurations.
"""
abstract type AbstractProblemConfig end

"""
Abstract base type for solvers.
"""
abstract type AbstractSolver end

# Core interface methods that each problem type must implement

"""
    generate_instance(problem_type::Type{<:AbstractBenchmarkProblem}, config::AbstractProblemConfig; rng, include_solution=false)

Generate a single instance of the given problem type.
"""
function generate_instance end

"""
    solve_instance(problem_type::Type{<:AbstractBenchmarkProblem}, instance, solver::AbstractSolver)

Solve a single problem instance using the specified solver.
"""
function solve_instance end

"""
    solve_instance(problem_type::Type{<:AbstractBenchmarkProblem}, instance)

Solve a single problem instance using the default solver.
"""
function solve_instance(problem_type::Type{<:AbstractBenchmarkProblem}, instance)
    solve_instance(problem_type, instance, default_solver(problem_type))
end

"""
    problem_id(instance)

Generate a stable ID for the instance.
"""
function problem_id end

"""
    default_configs(problem_type::Type{<:AbstractBenchmarkProblem})

Return default configurations for benchmarking this problem type.
"""
function default_configs end

"""
    config(problem_type::Type{<:AbstractBenchmarkProblem}, params)

Generate a configuration for the given problem type and parameters.
"""
function config end

"""
    filename_pattern(problem_type::Type{<:AbstractBenchmarkProblem}, config::AbstractProblemConfig)

Generate filename for dataset files.
"""
function filename_pattern end

"""
    available_solvers(problem_type::Type{<:AbstractBenchmarkProblem})

Return available solvers for this problem type.
"""
function available_solvers end

"""
    default_solver(problem_type::Type{<:AbstractBenchmarkProblem})

Return the default solver for this problem type.
"""
function default_solver end

"""
    solver_name(solver::AbstractSolver)

Return human-readable name for the solver.
"""
function solver_name end
