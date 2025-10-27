abstract type AbstractBenchmarkProblem end
abstract type AbstractProblemConfig end
abstract type AbstractSolver end

function generate_instance end
function solve_instance end
function solve_instance(problem_type::Type{<:AbstractBenchmarkProblem}, instance)
    solve_instance(problem_type, instance, default_solver(problem_type))
end
function problem_id end
function default_configs end
function config end
function filename_pattern end
function available_solvers end
function default_solver end
function verify_solution end
function solver_name end
