struct CNFSolverResult
    status::Symbol                 # :sat | :unsat | :unknown
    model::Union{Nothing, Dict{Int, Bool}}  # Variable -> value (present only when SAT)
    raw::String                    # Raw console output for debugging/logging
    decisions::Union{Nothing, Int}  # Number of decisions (branches) made by solver
end

function parse_dimacs_model(raw_output::String)::Dict{Int, Bool}
    model = Dict{Int, Bool}()
    # Parse lines starting with "v" (variable assignments in DIMACS format)
    for line in split(raw_output, '\n')
        if startswith(strip(line), "v")
            # Extract variable assignments: "v 1 -2 3 0" means var 1=true, var 2=false, var 3=true
            parts = split(strip(line))
            for part in parts[2:end]  # Skip the "v" prefix
                part = strip(part)
                if part == "0"  # End of model line
                    break
                end
                var_val = parse(Int, part)
                var_id = abs(var_val)
                model[var_id] = var_val > 0
            end
        end
    end
    return model
end

function parse_dimacs_output(solver::KissatSolver, raw_output::String)::CNFSolverResult
    # Parse status line
    status = if occursin(r"(?m)^s\s+SATISFIABLE\b", raw_output)
        :sat
    elseif occursin(r"(?m)^s\s+UNSATISFIABLE\b", raw_output)
        :unsat
    else
        :unknown
    end
    
    # Parse model if SAT
    model = status == :sat ? parse_dimacs_model(raw_output) : nothing
    
    # Parse decisions (branches) from kissat output
    # Example: "c decisions:                            13555                1.49 per conflict"
    decisions = nothing
    if !solver.quiet
        m = match(r"(?m)^c\s+decisions:\s+(\d+)", raw_output)
        if m !== nothing
            decisions = parse(Int, m.captures[1])
        end
    end
    
    return CNFSolverResult(status, model, raw_output, decisions)
end

function parse_dimacs_output(solver::MinisatSolver, raw_output::String)::CNFSolverResult
    # MiniSAT outputs status directly as "SATISFIABLE" or "UNSATISFIABLE" (no "s" prefix)
    status = if occursin(r"(?m)^SATISFIABLE\b", raw_output)
        :sat
    elseif occursin(r"(?m)^UNSATISFIABLE\b", raw_output)
        :unsat
    else
        :unknown
    end
    
    # Parse model if SAT
    model = status == :sat ? parse_dimacs_model(raw_output) : nothing
    
    # Parse decisions from MiniSAT output
    # Example: "decisions             : 13753          (0.00 % random) (75275 /sec)"
    decisions = nothing
    if !solver.quiet
        m = match(r"(?m)^decisions\s+:\s+(\d+)", raw_output)
        if m !== nothing
            decisions = parse(Int, m.captures[1])
        end
    end
    
    return CNFSolverResult(status, model, raw_output, decisions)
end


function run_kissat_and_parse(kissat_path::String, cnf_path::String, solver::KissatSolver)::CNFSolverResult
    # Kissat exit codes: 10=SAT, 20=UNSAT, 0=unknown/timeout, others=error
    # We need to capture output even when exit code is non-zero
    if solver.quiet
        cmd = `/opt/homebrew/bin/gtimeout $(solver.timeout)s $kissat_path -q $cnf_path`
    else
        cmd = `/opt/homebrew/bin/gtimeout $(solver.timeout)s $kissat_path $cnf_path`
    end
    # Capture stdout and stderr separately, allow non-zero exit codes
    stdout_pipe = Pipe()
    stderr_pipe = Pipe()
    proc = run(pipeline(cmd, stdout=stdout_pipe, stderr=stderr_pipe), wait=false)
    close(stdout_pipe.in)
    close(stderr_pipe.in)
    
    raw_stdout = read(stdout_pipe, String)
    raw_stderr = read(stderr_pipe, String)
    wait(proc)
    exitcode = proc.exitcode
    
    # Check for actual errors (not SAT/UNSAT exit codes)
    if exitcode != 0 && exitcode != 10 && exitcode != 20
        error("Kissat exited with error code $(exitcode). Stderr: $raw_stderr\nStdout: $raw_stdout")
    end
    
    return parse_dimacs_output(solver, raw_stdout)
end

function run_minisat_and_parse(minisat_path::String, cnf_path::String, solver::MinisatSolver)::CNFSolverResult
    # MiniSAT with -verb=0 for quiet mode (only outputs status)
    # MiniSAT exit codes: 10=SAT, 20=UNSAT, 0=unknown/timeout
    if solver.quiet
        cmd = `/opt/homebrew/bin/gtimeout $(solver.timeout)s $minisat_path -verb=0 $cnf_path`
    else
        cmd = `/opt/homebrew/bin/gtimeout $(solver.timeout)s $minisat_path $cnf_path`
    end
    
    # Capture stdout and stderr separately, allow non-zero exit codes
    stdout_pipe = Pipe()
    stderr_pipe = Pipe()
    proc = run(pipeline(cmd, stdout=stdout_pipe, stderr=stderr_pipe), wait=false)
    close(stdout_pipe.in)
    close(stderr_pipe.in)
    
    raw_stdout = read(stdout_pipe, String)
    raw_stderr = read(stderr_pipe, String)
    wait(proc)
    exitcode = proc.exitcode
    
    # Check for actual errors (not SAT/UNSAT exit codes)
    if exitcode != 0 && exitcode != 10 && exitcode != 20
        error("MiniSAT exited with error code $(exitcode). Stderr: $raw_stderr\nStdout: $raw_stdout")
    end
    
    return parse_dimacs_output(solver, raw_stdout)
end

function run_cnf_solver(solver::KissatSolver, cnf_path::String)::CNFSolverResult
    return run_kissat_and_parse(solver.kissat_path, cnf_path, solver)
end

function run_cnf_solver(solver::MinisatSolver, cnf_path::String)::CNFSolverResult
    return run_minisat_and_parse(solver.minisat_path, cnf_path, solver)
end
