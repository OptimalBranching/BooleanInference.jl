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

# Helper function to convert circuit to CNF using ABC
function circuit_to_cnf(circuit::Circuit, abc_path::Union{String, Nothing}, dir::String)
    vfile = joinpath(dir, "circuit.v")
    cnf_file = joinpath(dir, "circuit.cnf")
    
    write_verilog(vfile, circuit)
    
    if !isnothing(abc_path)
        run(`$abc_path -c "read_verilog $vfile; strash; &get; &write_cnf -K 8 $cnf_file"`)
    else
        error("ABC path is required for CNF conversion but not provided")
    end
    return cnf_file
end

# Generic implementation for CNF solvers
function solve_instance(::Type{FactoringProblem}, instance::FactoringInstance, solver::CNFSolver)
    m, n = instance.m, instance.n
    fproblem = Factoring(m, n, instance.N)
    circuit_sat = reduceto(CircuitSAT, fproblem)

    mktempdir() do dir
        cnf_file = circuit_to_cnf(circuit_sat.circuit.circuit, solver.abc_path, dir)
        
        res = run_cnf_solver(solver, cnf_file)
        return res.status
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

