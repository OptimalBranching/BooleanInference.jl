function solve_instance(::Type{FactoringProblem}, instance::FactoringInstance, solver::BooleanInferenceSolver)
    return BooleanInference.solve_factoring(instance.m, instance.n, Int(instance.N))
end

function solve_instance(::Type{FactoringProblem}, instance::FactoringInstance, solver::IPSolver)
    return factoring_ip(instance.m, instance.n, Int(instance.N); solver)
end

function solve_instance(::Type{FactoringProblem}, instance::FactoringInstance, solver::XSATSolver)
    m, n = instance.m, instance.n
    fproblem = Factoring(m, n, instance.N)
    circuit_sat = reduceto(CircuitSAT, fproblem)

    mktempdir() do dir
        vfile = joinpath(dir, "circuit.v")
        aig   = joinpath(dir, "circuit.aig")
    
        write_verilog(vfile, circuit_sat.circuit.circuit) 
    
        run(`$(solver.yosys_path) -q -p "read_verilog $vfile; prep -top circuit; aigmap; write_aiger -symbols $aig"`)
    
        res = run_xsat_and_parse(solver.csat_path, aig)
        res.status != :sat && return :unsat
        
        model = res.model::Dict{Int,Bool}

        bits_p = [get(model, i, false) for i in 1:m]
        bits_q = [get(model, i, false) for i in m+1:m+n]

        p_val = sum(Int(bit) << (i-1) for (i, bit) in enumerate(bits_p))
        q_val = sum(Int(bit) << (i-1) for (i, bit) in enumerate(bits_q))

        return (p_val, q_val)
    end
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

