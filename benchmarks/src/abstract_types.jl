# Abstract types and interfaces for benchmark problems

"""
Abstract base type for all benchmark problems.
"""
abstract type AbstractBenchmarkProblem end

"""
Abstract base type for problem configurations.
"""
abstract type AbstractProblemConfig end

# Core interface methods that each problem type must implement

"""
    generate_instance(problem_type::Type{<:AbstractBenchmarkProblem}, config::AbstractProblemConfig; rng, include_solution=false)

Generate a single instance of the given problem type.
"""
function generate_instance end

"""
    solve_instance(problem_type::Type{<:AbstractBenchmarkProblem}, instance)

Solve a single problem instance.
"""
function solve_instance end

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
    filename_pattern(problem_type::Type{<:AbstractBenchmarkProblem}, config::AbstractProblemConfig)

Generate filename for dataset files.
"""
function filename_pattern end
