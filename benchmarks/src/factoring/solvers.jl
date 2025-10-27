using BooleanInference

function solve_instance(::Type{FactoringProblem}, instance, solver::BooleanInferenceSolver)
    m = instance["m"]
    n = instance["n"]
    N = parse(Int, instance["N"])
    return BooleanInference.solve_factoring(m, n, N)
end

function solve_instance(::Type{FactoringProblem}, instance, solver::IPSolver)
    m = instance["m"]
    n = instance["n"]
    N = parse(Int, instance["N"])
    return factoring_ip(m, n, N; optimizer=solver.optimizer, env=solver.env)
end

function verify_solution(::Type{FactoringProblem}, instance, result)
    try
        N = parse(Int, instance["N"])
        if result isa Tuple
            p = result[1]; q = result[2];
        else
            @warn "Unknown result format: $(typeof(result))"
            return false
        end
        if p * q == N
            return true
        else
            @warn "Incorrect factorization: $p × $q = $(p*q) ≠ $N"
            return false
        end
    catch e
        @warn "Error verifying solution: $e"
        return false
    end
end

function solver_name(::BooleanInferenceSolver)
    return "BI"
end

function solver_name(solver::IPSolver)
    return "IP-$(string(solver.optimizer)[1:end-10])"
end

