# ============================================================================
# solvers.jl - All solve_instance implementations
# ============================================================================

# ============================================================================
# BooleanInference Solver
# ============================================================================

function solve_instance(::Type{FactoringProblem}, inst::FactoringInstance, solver::BooleanInferenceSolver)
    BooleanInference.solve_factoring(inst.m, inst.n, Int(inst.N);
        bsconfig=solver.bsconfig, reducer=solver.reducer, show_stats=solver.show_stats, cdcl_cutoff=solver.cdcl_cutoff)
end

function solve_instance(::Type{CircuitSATProblem}, inst::CircuitSATInstance, solver::BooleanInferenceSolver)
    t0 = time()
    found, stats = BooleanInference.solve_circuit_sat(inst.circuit;
        bsconfig=solver.bsconfig, reducer=solver.reducer, show_stats=solver.show_stats)
    elapsed = time() - t0

    status = found ? SAT : UNSAT
    SolveResult(status, nothing, elapsed,
        stats.branch_points,
        stats.gamma_one_count,
        stats.avg_vars_per_branch,
        stats.vars_by_gamma_one,
        stats.vars_by_branches,
        "BI")
end

function solve_instance(::Type{CNFSATProblem}, inst::CNFSATInstance, solver::BooleanInferenceSolver)
    sat = cnf_instantiation(inst)  # Returns Satisfiability object

    # Try to set up and solve - may throw if UNSAT detected during propagation
    try
        tn_problem = BooleanInference.setup_from_sat(sat)
        BooleanInference.solve(tn_problem, solver.bsconfig, solver.reducer; show_stats=solver.show_stats, cdcl_cutoff=solver.cdcl_cutoff)
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

function _run_cnf_solver(cmd::Cmd, output_pattern::Regex, decision_pattern::Regex;
                         conflict_pattern::Regex=r"(?m)^c\s+conflicts:\s+(\d+)")
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
    conflicts = (m = match(conflict_pattern, raw); isnothing(m) ? nothing : parse(Int, m.captures[1]))

    CNFSolverResult(status, model, raw, decisions, conflicts)
end

function _write_cnf_dimacs(path::String, cnf::Vector{<:AbstractVector{<:Integer}}, nvars::Int)
    open(path, "w") do io
        println(io, "p cnf $nvars $(length(cnf))")
        for clause in cnf
            for lit in clause
                print(io, lit, " ")
            end
            println(io, "0")
        end
    end
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
        cnf_path = joinpath(dir, "circuit.cnf")
        cnf, symbols = circuit_to_cnf(inst.circuit)
        nvars = length(symbols)
        for clause in cnf
            for lit in clause
                nvars = max(nvars, abs(Int(lit)))
            end
        end
        _write_cnf_dimacs(cnf_path, cnf, nvars)
        run_cnf_solver(solver, cnf_path)
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
    # Use a persistent temp file to avoid race conditions with subprocesses
    cnf_path = tempname() * ".cnf"
    try
        fproblem = Factoring(inst.m, inst.n, inst.N)
        reduction = reduceto(CircuitSAT, fproblem)
        cnf, symbols = circuit_to_cnf(reduction.circuit.circuit)

        # Get p and q variable indices
        p_vars = collect(reduction.p)
        q_vars = collect(reduction.q)

        nvars = length(symbols)
        for clause in cnf
            for lit in clause
                nvars = max(nvars, abs(Int(lit)))
            end
        end
        _write_cnf_dimacs(cnf_path, cnf, nvars)
        @assert isfile(cnf_path) "CNF file was not created at $cnf_path"

        result = run_cnf_solver(solver, cnf_path)

        # Extract factors from solution model
        if result.status == :sat && !isnothing(result.model)
            p = 0
            q = 0
            for (i, var_idx) in enumerate(p_vars)
                if get(result.model, var_idx, false)
                    p |= (1 << (i - 1))
                end
            end
            for (i, var_idx) in enumerate(q_vars)
                if get(result.model, var_idx, false)
                    q |= (1 << (i - 1))
                end
            end
            return (p, q, result)
        else
            return (nothing, nothing, result)
        end
    finally
        rm(cnf_path, force=true)
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

    CNFSolverResult(status, model, raw, num_cubes, nothing)  # march_cu doesn't report conflicts
end

# CnC (Cube and Conquer) solver
# Uses march_cu for cube generation and kissat for solving
function run_cnf_solver(solver::CnCSolver, cnf_path::String)::CnCResult
    cubes_file = something(solver.cubes_file, tempname() * ".cubes")

    # Build march_cu command: march_cu <input-file> [options]
    # Input file must come immediately after the executable
    march_cmd = [solver.march_cu_path, cnf_path]
    solver.cutoff_depth > 0 && append!(march_cmd, ["-d", string(solver.cutoff_depth)])
    solver.cutoff_nvars > 0 && append!(march_cmd, ["-n", string(solver.cutoff_nvars)])
    solver.down_exponent != 0.30 && append!(march_cmd, ["-e", string(solver.down_exponent)])
    solver.down_fraction != 0.02 && append!(march_cmd, ["-f", string(solver.down_fraction)])
    solver.max_cubes > 0 && append!(march_cmd, ["-l", string(solver.max_cubes)])
    append!(march_cmd, ["-o", cubes_file])

    # Generate cubes with timing
    cubing_time = @elapsed begin
        stdout_pipe, stderr_pipe = Pipe(), Pipe()
        proc = run(pipeline(Cmd(march_cmd), stdout=stdout_pipe, stderr=stderr_pipe), wait=false)
        close(stdout_pipe.in)
        close(stderr_pipe.in)
        march_output = read(stdout_pipe, String)
        wait(proc)
    end

    # Check if UNSAT detected during cube generation
    if occursin("UNSATISFIABLE", march_output)
        stats = CnCStats(0, 0, cubing_time, 0.0, 0, 0.0, 0.0, 0.0, 0.0)
        return CnCResult(:unsat, nothing, stats, march_output, Int[])
    end

    # Parse march_cu statistics
    cubes_match = match(r"c number of cubes (\d+), including (\d+) refuted", march_output)
    num_cubes = isnothing(cubes_match) ? 0 : parse(Int, cubes_match.captures[1])
    num_refuted = isnothing(cubes_match) ? 0 : parse(Int, cubes_match.captures[2])

    # Read and solve cubes
    if !isfile(cubes_file) || num_cubes == 0
        stats = CnCStats(num_cubes, num_refuted, cubing_time, 0.0, 0, 0.0, 0.0, 0.0, 0.0)
        return CnCResult(:unknown, nothing, stats, march_output, Int[])
    end

    cubes = readlines(cubes_file)

    # Extract branching variables from cubes (in order of first appearance)
    branching_vars = Int[]
    seen_vars = Set{Int}()
    for cube in cubes
        isempty(strip(cube)) && continue
        startswith(cube, "a") || continue
        for lit_str in split(cube)[2:end]
            lit_str = strip(lit_str)
            lit_str == "0" && break
            var = abs(parse(Int, lit_str))
            if var ∉ seen_vars
                push!(branching_vars, var)
                push!(seen_vars, var)
            end
        end
    end
    @info "march_cu branching variables" n_vars=length(branching_vars) first_10=branching_vars[1:min(10,length(branching_vars))]

    # Read original CNF and parse header for proper clause count adjustment
    cnf_lines = readlines(cnf_path)

    # Statistics tracking
    total_cube_vars = 0
    cubes_solved = 0
    total_decisions = 0
    total_conflicts = 0
    total_solve_time = 0.0
    all_output = march_output

    for cube in cubes
        isempty(strip(cube)) && continue
        startswith(cube, "a") || continue

        # Parse cube literals (skip 'a' prefix and trailing '0')
        cube_lits = String[]
        for lit in split(cube)[2:end]
            lit = strip(lit)
            lit == "0" && break
            push!(cube_lits, lit)
        end
        isempty(cube_lits) && continue
        total_cube_vars += length(cube_lits)

        # Create CNF with cube as unit clauses
        cube_cnf = tempname() * ".cnf"
        open(cube_cnf, "w") do io
            for line in cnf_lines
                # Update the p-line to include cube clauses
                if startswith(line, "p cnf")
                    parts = split(line)
                    nvars = parse(Int, parts[3])
                    nclauses = parse(Int, parts[4]) + length(cube_lits)
                    println(io, "p cnf $nvars $nclauses")
                else
                    println(io, line)
                end
            end
            # Add cube literals as unit clauses
            for lit in cube_lits
                println(io, "$lit 0")
            end
        end

        # Run kissat on this cube with timing
        kissat_cmd = `$(solver.kissat_path) $cube_cnf`
        cube_time = @elapsed begin
            kissat_result = _run_cnf_solver(kissat_cmd, r"(?m)^s\s+SATISFIABLE", r"(?m)^c\s+decisions:\s+(\d+)")
        end

        rm(cube_cnf, force=true)
        cubes_solved += 1
        total_solve_time += cube_time
        total_decisions += something(kissat_result.decisions, 0)

        # Parse conflicts from kissat output
        conflicts_match = match(r"c\s+conflicts:\s+(\d+)", kissat_result.raw)
        total_conflicts += isnothing(conflicts_match) ? 0 : parse(Int, conflicts_match.captures[1])

        if kissat_result.status == :sat
            rm(cubes_file, force=true)
            avg_cube_vars = cubes_solved > 0 ? total_cube_vars / cubes_solved : 0.0
            avg_decisions = cubes_solved > 0 ? total_decisions / cubes_solved : 0.0
            avg_conflicts = cubes_solved > 0 ? total_conflicts / cubes_solved : 0.0
            avg_solve_time = cubes_solved > 0 ? total_solve_time / cubes_solved : 0.0
            stats = CnCStats(num_cubes, num_refuted, cubing_time, avg_cube_vars,
                           cubes_solved, avg_decisions, avg_conflicts, avg_solve_time, total_solve_time)
            return CnCResult(:sat, kissat_result.model, stats, all_output * "\n" * kissat_result.raw, branching_vars)
        end
    end

    rm(cubes_file, force=true)

    # Calculate final statistics
    num_valid_cubes = num_cubes - num_refuted
    avg_cube_vars = num_valid_cubes > 0 ? total_cube_vars / num_valid_cubes : 0.0
    avg_decisions = cubes_solved > 0 ? total_decisions / cubes_solved : 0.0
    avg_conflicts = cubes_solved > 0 ? total_conflicts / cubes_solved : 0.0
    avg_solve_time = cubes_solved > 0 ? total_solve_time / cubes_solved : 0.0
    stats = CnCStats(num_cubes, num_refuted, cubing_time, avg_cube_vars,
                   cubes_solved, avg_decisions, avg_conflicts, avg_solve_time, total_solve_time)

    # If no cube is SAT, problem is UNSAT
    CnCResult(:unsat, nothing, stats, all_output, branching_vars)
end

# CryptoMiniSat solver
function run_cnf_solver(solver::CryptoMiniSatSolver, cnf_path::String)
    cmd_parts = [solver.cryptominisat_path]
    solver.threads > 1 && append!(cmd_parts, ["-t", string(solver.threads)])
    solver.quiet && push!(cmd_parts, "--verb=0")
    push!(cmd_parts, cnf_path)

    base_cmd = `/opt/homebrew/bin/gtimeout $(solver.timeout)s`
    cmd = `$base_cmd $(Cmd(cmd_parts))`

    stdout_pipe, stderr_pipe = Pipe(), Pipe()
    proc = run(pipeline(cmd, stdout=stdout_pipe, stderr=stderr_pipe), wait=false)
    close(stdout_pipe.in)
    close(stderr_pipe.in)
    raw = read(stdout_pipe, String)
    wait(proc)

    status = if occursin(r"(?m)^s\s*SATISFIABLE", raw)
        :sat
    elseif occursin(r"(?m)^s\s*UNSATISFIABLE", raw)
        :unsat
    else
        :unknown
    end

    model = status == :sat ? _parse_dimacs_model(raw) : nothing

    # Parse decisions and conflicts from CryptoMiniSat output
    decisions_match = match(r"c\s+decisions\s*:\s*(\d+)", raw)
    decisions = isnothing(decisions_match) ? nothing : parse(Int, decisions_match.captures[1])
    conflicts_match = match(r"c\s+conflicts\s*:\s*(\d+)", raw)
    conflicts = isnothing(conflicts_match) ? nothing : parse(Int, conflicts_match.captures[1])

    CNFSolverResult(status, model, raw, decisions, conflicts)
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
        NoReducer(), false, 0.8)  # cdcl_cutoff=0.8 for factoring
end

function default_solver(::Type{CircuitSATProblem})
    BooleanInferenceSolver(
        BranchingStrategy(table_solver=TNContractionSolver(), selector=MostOccurrenceSelector(3, 6),
            measure=NumUnfixedVars(), set_cover_solver=GreedyMerge()),
        NoReducer(), false, 1.0)  # cdcl_cutoff=1.0 (disabled) for circuit
end

default_solver(::Type{CNFSATProblem}) = default_solver(CircuitSATProblem)
