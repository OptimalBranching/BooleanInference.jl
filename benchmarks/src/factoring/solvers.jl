function solve_instance(::Type{FactoringProblem}, instance::FactoringInstance, solver::BooleanInferenceSolver)
    return BooleanInference.solve_factoring(instance.m, instance.n, Int(instance.N))
end

function solve_instance(::Type{FactoringProblem}, instance::FactoringInstance, solver::IPSolver)
    return factoring_ip(instance.m, instance.n, Int(instance.N); optimizer=solver.optimizer, env=solver.env)
end

function verify_solution(::Type{FactoringProblem}, instance::FactoringInstance, result)
    try
        if result isa Tuple
            p = result[1]; q = result[2];
        else
            @warn "Unknown result format: $(typeof(result))"
            return false
        end
        if p * q == instance.N
            return true
        else
            @warn "Incorrect factorization: $p × $q = $(p*q) ≠ $(instance.N)"
            return false
        end
    catch e
        @warn "Error verifying solution: $e"
        return false
    end
end

