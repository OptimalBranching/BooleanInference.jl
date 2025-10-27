using SHA: bytes2hex, sha1

function problem_id(::Type{FactoringProblem}, config::FactoringConfig, N::Integer)
    h = bytes2hex(sha1(string(config.m, "|", config.n, "|", N)))
    return h[1:16]
end

function default_configs(::Type{FactoringProblem})
    return FactoringConfig[
        FactoringConfig(10, 10),
        FactoringConfig(12, 12),
        FactoringConfig(14, 14),
     ]
end

function config(::Type{FactoringProblem}, params::Tuple{Int,Int})
    return FactoringConfig(params[1], params[2])
end

function filename_pattern(::Type{FactoringProblem}, config::FactoringConfig)
    return "numbers_$(config.m)x$(config.n).jsonl"
end

function available_solvers(::Type{FactoringProblem})
    return [BooleanInferenceSolver(), IPSolver(), IPSolver(HiGHS.Optimizer)]
end

function default_solver(::Type{FactoringProblem})
    return BooleanInferenceSolver()
end

