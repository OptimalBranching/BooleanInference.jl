# ============================================================================
# solvers.jl - All solve_instance implementations
# ============================================================================

# ============================================================================
# BooleanInference Solver
# ============================================================================

function solve_instance(::Type{FactoringProblem}, inst::FactoringInstance, solver::BooleanInferenceSolver)
    BooleanInference.solve_factoring(inst.m, inst.n, Int(inst.N);
        bsconfig=solver.bsconfig, reducer=solver.reducer, show_stats=solver.show_stats,
        use_cdcl=solver.use_cdcl, conflict_limit=solver.conflict_limit, max_clause_len=solver.max_clause_len)
end

function solve_instance(::Type{CircuitSATProblem}, inst::CircuitSATInstance, solver::BooleanInferenceSolver)
    BooleanInference.solve_circuit_sat(inst.circuit;
        bsconfig=solver.bsconfig, reducer=solver.reducer, show_stats=solver.show_stats,
        use_cdcl=solver.use_cdcl, conflict_limit=solver.conflict_limit, max_clause_len=solver.max_clause_len)
end

function solve_instance(::Type{CNFSATProblem}, inst::CNFSATInstance, solver::BooleanInferenceSolver)
    sat = cnf_instantiation(inst)  # Returns Satisfiability object

    # Try to set up and solve - may throw if UNSAT detected during propagation
    try
        tn_problem = BooleanInference.setup_from_sat(sat)
        BooleanInference.solve(tn_problem, solver.bsconfig, solver.reducer; show_stats=solver.show_stats)
    catch e
        if occursin("contradiction", string(e))
            # UNSAT detected during propagation - return early UNSAT result
            return BooleanInference.Result(false, BooleanInference.DomainMask[], BooleanInference.BranchingStats())
        else
            rethrow(e)
        end
    end
end

# ============================================================================
# IP Solver
# ============================================================================

function solve_instance(::Type{FactoringProblem}, inst::FactoringInstance, solver::IPSolver)
    m, n, N = inst.m, inst.n, inst.N
    model = JuMP.Model(solver.optimizer)
    isnothing(solver.env) || MOI.set(model, MOI.RawOptimizerAttribute("env"), solver.env)
    set_silent(model)

    @variable(model, p_bits[1:m], Bin)
    @variable(model, q_bits[1:n], Bin)
    @variable(model, carry[1:m+n], Bin)

    p_val = sum(p_bits[i] * 2^(i - 1) for i in 1:m)
    q_val = sum(q_bits[i] * 2^(i - 1) for i in 1:n)
    @constraint(model, p_val * q_val == N)

    optimize!(model)

    if termination_status(model) == MOI.OPTIMAL
        p = sum(Int(round(value(p_bits[i]))) * 2^(i - 1) for i in 1:m)
        q = sum(Int(round(value(q_bits[i]))) * 2^(i - 1) for i in 1:n)
        (p, q, nothing)
    else
        (nothing, nothing, nothing)
    end
end

# ============================================================================
# CNF Solvers (Kissat, Minisat)
# ============================================================================

function _parse_dimacs_model(output::String)
    model = Dict{Int,Bool}()
    for line in split(output, '\n')
        if startswith(strip(line), "v")
            for part in split(strip(line))[2:end]
                part = strip(part)
                part == "0" && break
                val = parse(Int, part)
                model[abs(val)] = val > 0
            end
        end
    end
    model
end

function _run_cnf_solver(cmd::Cmd, output_pattern::Regex, decision_pattern::Regex)
    stdout_pipe, stderr_pipe = Pipe(), Pipe()
    proc = run(pipeline(cmd, stdout=stdout_pipe, stderr=stderr_pipe), wait=false)
    close(stdout_pipe.in)
    close(stderr_pipe.in)
    raw = read(stdout_pipe, String)
    wait(proc)

    status = if occursin(r"(?m)^s?\s*SATISFIABLE", raw)
        :sat
    elseif occursin(r"(?m)^s?\s*UNSATISFIABLE", raw)
        :unsat
    else
        :unknown
    end

    model = status == :sat ? _parse_dimacs_model(raw) : nothing
    decisions = (m = match(decision_pattern, raw); isnothing(m) ? nothing : parse(Int, m.captures[1]))

    CNFSolverResult(status, model, raw, decisions)
end

function run_cnf_solver(solver::KissatSolver, cnf_path::String)
    base_cmd = `/opt/homebrew/bin/gtimeout $(solver.timeout)s $(solver.kissat_path)`
    cmd = solver.quiet ? `$base_cmd -q $cnf_path` : `$base_cmd $cnf_path`
    _run_cnf_solver(cmd, r"(?m)^s\s+SATISFIABLE", r"(?m)^c\s+decisions:\s+(\d+)")
end

function run_cnf_solver(solver::MinisatSolver, cnf_path::String)
    base_cmd = `/opt/homebrew/bin/gtimeout $(solver.timeout)s $(solver.minisat_path)`
    cmd = solver.quiet ? `$base_cmd -verb=0 $cnf_path` : `$base_cmd $cnf_path`
    _run_cnf_solver(cmd, r"(?m)^decisions\s+:\s+(\d+)", r"(?m)^decisions\s+:\s+(\d+)")
end

# CNF Solver for CircuitSAT - converts circuit to CNF first
function solve_instance(::Type{CircuitSATProblem}, inst::CircuitSATInstance, solver::CNFSolver)
    mktempdir() do dir
        vfile, aig, cnf = joinpath(dir, "circuit.v"), joinpath(dir, "circuit.aig"), joinpath(dir, "circuit.cnf")
        write_verilog(vfile, inst.circuit)
        run(pipeline(`yosys -q -p "read_verilog $vfile; prep -top circuit; aigmap; write_aiger -symbols $aig"`,
            stdout=devnull, stderr=devnull))
        abc_path = solver isa KissatSolver ? solver.abc_path : solver.minisat_path
        abc_path = solver isa KissatSolver ? solver.abc_path : solver.abc_path
        run(`$(abc_path) -c "read_aiger $aig; strash; &get; &write_cnf -K 8 $cnf"`)
        run_cnf_solver(solver, cnf)
    end
end

function solve_instance(::Type{CNFSATProblem}, inst::CNFSATInstance, solver::CNFSolver)
    # If source_path is a real file, use it directly
    if isfile(inst.source_path)
        return run_cnf_solver(solver, inst.source_path)
    end

    # Otherwise, write a temporary CNF file
    mktempdir() do dir
        cnf_path = joinpath(dir, "temp.cnf")
        open(cnf_path, "w") do io
            println(io, "p cnf $(inst.num_vars) $(length(inst.clauses))")
            for clause in inst.clauses
                println(io, join(clause, " ") * " 0")
            end
        end
        run_cnf_solver(solver, cnf_path)
    end
end

function solve_instance(::Type{FactoringProblem}, inst::FactoringInstance, solver::CNFSolver)
    mktempdir() do dir
        fproblem = Factoring(inst.m, inst.n, inst.N)
        circuit_sat = reduceto(CircuitSAT, fproblem)
        vfile, cnf = joinpath(dir, "circuit.v"), joinpath(dir, "circuit.cnf")
        write_verilog(vfile, circuit_sat.circuit.circuit)
        abc_path = solver isa KissatSolver ? solver.abc_path : solver.abc_path
        run(`$abc_path -c "read_verilog $vfile; strash; &get; &write_cnf -K 8 $cnf"`)
        run_cnf_solver(solver, cnf)
    end
end

# MarchCu (Cube and Conquer) solver
# march_cu is a complete solver: it generates cubes and solves them internally
function run_cnf_solver(solver::MarchCuSolver, cnf_path::String)
    # Run march_cu directly - it will solve the problem
    stdout_pipe, stderr_pipe = Pipe(), Pipe()
    cmd = `$(solver.march_cu_path) $cnf_path`
    proc = run(pipeline(cmd, stdout=stdout_pipe, stderr=stderr_pipe), wait=false)
    close(stdout_pipe.in)
    close(stderr_pipe.in)
    raw = read(stdout_pipe, String)
    wait(proc)

    # Parse status
    status = if occursin(r"(?m)^s\s+SATISFIABLE", raw)
        :sat
    elseif occursin(r"(?m)^s\s+UNSATISFIABLE", raw) || occursin("UNSATISFIABLE", raw)
        :unsat
    else
        :unknown
    end

    # Parse model if SAT
    model = nothing
    if status == :sat
        model = Dict{Int,Bool}()
        for line in split(raw, '\n')
            if startswith(strip(line), "v")
                for part in split(strip(line))[2:end]
                    part = strip(part)
                    part == "0" && break
                    val = parse(Int, part)
                    model[abs(val)] = val > 0
                end
            end
        end
    end

    # Parse statistics: number of cubes as "decisions" equivalent
    cubes_match = match(r"c number of cubes (\d+)", raw)
    num_cubes = isnothing(cubes_match) ? nothing : parse(Int, cubes_match.captures[1])

    CNFSolverResult(status, model, raw, num_cubes)
end


# ============================================================================
# X-SAT Solver
# ============================================================================

function solve_instance(::Type{FactoringProblem}, inst::FactoringInstance, solver::XSATSolver)
    mktempdir() do dir
        fproblem = Factoring(inst.m, inst.n, inst.N)
        circuit_sat = reduceto(CircuitSAT, fproblem)
        vfile, aig = joinpath(dir, "circuit.v"), joinpath(dir, "circuit.aig")
        write_verilog(vfile, circuit_sat.circuit.circuit)
        run(`$(solver.yosys_path) -q -p "read_verilog $vfile; prep -top circuit; aigmap; write_aiger -symbols $aig"`)

        # Run X-SAT
        output = read(`$timeout $(solver.timeout)s $(solver.csat_path) $aig`, String)
        # Parse result... (simplified)
        if occursin("SAT", output)
            # Extract bits (simplified)
            (nothing, nothing, nothing)  # Would need proper parsing
        else
            (nothing, nothing, nothing)
        end
    end
end

# ============================================================================
# Default solver
# ============================================================================

function default_solver(::Type{FactoringProblem})
    BooleanInferenceSolver(
        BranchingStrategy(table_solver=TNContractionSolver(), selector=MostOccurrenceSelector(3, 6),
            measure=NumUnfixedVars(), set_cover_solver=GreedyMerge()),
        NoReducer(), false, true, 40000, 5)  # use_cdcl=true for factoring
end

function default_solver(::Type{CircuitSATProblem})
    BooleanInferenceSolver(
        BranchingStrategy(table_solver=TNContractionSolver(), selector=MostOccurrenceSelector(3, 6),
            measure=NumUnfixedVars(), set_cover_solver=GreedyMerge()),
        NoReducer(), false, false, 40000, 5)  # use_cdcl=false for circuit
end

default_solver(::Type{CNFSATProblem}) = default_solver(CircuitSATProblem)
