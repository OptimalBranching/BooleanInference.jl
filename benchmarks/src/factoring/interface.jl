# ----------------------------------------
# Factoring Problem Interface
# ----------------------------------------

# Helper for generating problem IDs
function problem_id(config::FactoringConfig, N::Integer)
    h = bytes2hex(sha1(string(config.m, "|", config.n, "|", N)))
    return h[1:16]
end

# Dataset filename pattern
function filename_pattern(::Type{FactoringProblem}, config::FactoringConfig)
    return "numbers_$(config.m)x$(config.n).jsonl"
end

# Solvers
function available_solvers(::Type{FactoringProblem})
    return [BooleanInferenceSolver(), IPSolver(), IPSolver(HiGHS.Optimizer), XSATSolver()]
end

function default_solver(::Type{FactoringProblem})
    return BooleanInferenceSolver()
end