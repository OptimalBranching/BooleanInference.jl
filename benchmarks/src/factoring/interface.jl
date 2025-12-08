# Dataset filename pattern
function filename_pattern(::Type{FactoringProblem}, config::FactoringConfig)
    return "numbers_$(config.m)x$(config.n).txt"
end

# Solvers
function available_solvers(::Type{FactoringProblem})
    return [BooleanInferenceSolver(), IPSolver(), IPSolver(HiGHS.Optimizer), XSATSolver()]
end

function default_solver(::Type{FactoringProblem})
    return BooleanInferenceSolver()
end