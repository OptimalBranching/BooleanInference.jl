# Interface functions for CircuitSAT benchmarking

# Solvers available for CircuitSAT
function available_solvers(::Type{CircuitSATProblem})
    return [BooleanInferenceSolver()]
end

function default_solver(::Type{CircuitSATProblem})
    return BooleanInferenceSolver()
end

# Problem identification
function problem_id(config::CircuitSATConfig)
    return basename(config.path)
end

# Load a single circuit instance from file
function load_circuit_instance(config::CircuitSATConfig; yosys_path::Union{String, Nothing}=nothing)
    name = problem_id(config)
    
    circuit = if config.format == :verilog
        CircuitIO.verilog_to_circuit(config.path)
    elseif config.format == :aag
        # Convert AAG to Verilog using Yosys for better performance
        circuit = aag_to_circuit_via_yosys(config.path; yosys_path=yosys_path)
    else
        error("Unsupported format: $(config.format)")
    end
    
    return CircuitSATInstance(name, circuit, config.format, config.path)
end

# Convert AAG to Circuit via Yosys (AAG -> Verilog -> Circuit)
function aag_to_circuit_via_yosys(aag_path::String; yosys_path::Union{String, Nothing}=nothing)
    # Find yosys executable
    yosys_exe = if !isnothing(yosys_path)
        yosys_path
    else
        # Try common paths
        common_paths = ["/opt/homebrew/bin/yosys", "/usr/local/bin/yosys", "/usr/bin/yosys"]
        found_path = nothing
        for path in common_paths
            if isfile(path)
                found_path = path
                break
            end
        end
        if !isnothing(found_path)
            found_path
        else
            # Try which command
            try
                strip(read(`which yosys`, String))
            catch
                "yosys"  # Fallback to PATH
            end
        end
    end
    
    # Create temporary Verilog file
    mktempdir() do tmpdir
        verilog_tmp = joinpath(tmpdir, "circuit_tmp.v")
        
        # Ensure the temporary directory exists and get absolute paths
        aag_abs = abspath(aag_path)
        verilog_abs = abspath(verilog_tmp)
        
        # Ensure the temporary directory exists
        mkpath(dirname(verilog_abs))
        
        # Use Yosys to convert AAG to Verilog with clean module name
        # The 'rename' command ensures we get a simple module name
        # Build command using array form to avoid quote issues
        yosys_script = "read_aiger $aag_abs; rename -top circuit_top; write_verilog $verilog_abs"
        yosys_cmd = Cmd([yosys_exe, "-p", yosys_script])
        
        try
            # Run Yosys conversion, capture stderr to see errors
            result = run(pipeline(yosys_cmd, stdout=stdout, stderr=stderr), wait=false)
            wait(result)
            
            if !success(result)
                error("Yosys command failed with exit code $(result.exitcode)")
            end
            
            # Verify the file was created
            if !isfile(verilog_abs)
                error("Yosys did not create output file: $verilog_abs")
            end
            
            # Parse the generated Verilog
            circuit = CircuitIO.verilog_to_circuit(verilog_abs)
            
            # Add constraints for outputs (po* variables must be true)
            # This is the standard CircuitSAT problem formulation
            circuit = add_output_constraints(circuit)
            
            return circuit
        catch e
            @error "Failed to convert AAG via Yosys" exception=e
            # Fallback to direct AAG parsing
            @warn "Falling back to direct AAG parsing (may be slower)"
            aig = CircuitIO.read_aag(aag_path)
            return CircuitIO.aig_to_circuit(aig)
        end
    end
end

# Add constraints that all outputs (po* variables) must be true
function add_output_constraints(circuit::Circuit)
    # Find all output variables (po* symbols)
    output_syms = Symbol[]
    for expr in circuit.exprs
        for out in expr.outputs
            out_str = String(out)
            if startswith(out_str, "po") && !(out in output_syms)
                push!(output_syms, out)
            end
        end
    end
    
    # Add constraint for each output
    for out_sym in output_syms
        push!(circuit.exprs, Assignment([out_sym], BooleanExpr(true)))
    end
    
    return circuit
end

# Read instances from a config (for compatibility with benchmark API)
function read_instances(::Type{CircuitSATProblem}, config::CircuitSATConfig)
    return [load_circuit_instance(config)]
end

# Read instances from a directory path (for benchmark_dataset)
function read_instances(::Type{CircuitSATProblem}, path::AbstractString; yosys_path::Union{String, Nothing}=nothing)
    if isfile(path)
        # Single file: determine format from extension
        format = if endswith(path, ".v")
            :verilog
        elseif endswith(path, ".aag")
            :aag
        else
            error("Unknown file format for: $path. Expected .v or .aag")
        end
        config = CircuitSATConfig(format, path)
        return [load_circuit_instance(config; yosys_path=yosys_path)]
    elseif isdir(path)
        # Directory: load all circuit files
        verilog_files = discover_circuit_files(path; format=:verilog)
        aag_files = discover_circuit_files(path; format=:aag)
        
        instances = CircuitSATInstance[]
        
        for vfile in verilog_files
            try
                config = CircuitSATConfig(:verilog, vfile)
                push!(instances, load_circuit_instance(config; yosys_path=yosys_path))
            catch e
                @warn "Failed to load $vfile" exception=e
            end
        end
        
        for afile in aag_files
            try
                config = CircuitSATConfig(:aag, afile)
                push!(instances, load_circuit_instance(config; yosys_path=yosys_path))
            catch e
                @warn "Failed to load $afile" exception=e
            end
        end
        
        return instances
    else
        error("Path not found: $path")
    end
end

# Generate a single instance (for compatibility, just loads the file)
function generate_instance(::Type{CircuitSATProblem}, config::CircuitSATConfig; kwargs...)
    return load_circuit_instance(config)
end

# Verify solution
function verify_solution(::Type{CircuitSATProblem}, instance::CircuitSATInstance, result)
    # Check if we got a valid result (tuple of (satisfiable, stats))
    if result === nothing
        return false
    end
    
    # solve_circuit_sat returns (satisfiable::Bool, stats)
    # We consider it successful if the solver ran without errors
    return true
end

# Helper function to check if the circuit is satisfiable
function is_satisfiable(result)
    if result === nothing
        return nothing  # Solver failed
    end
    
    # Handle different result types
    if result isa XSatResult
        return result.status == :sat ? true : (result.status == :unsat ? false : nothing)
    elseif result isa Tuple && length(result) >= 1
        satisfiable, _ = result
        return satisfiable  # true = SAT, false = UNSAT
    else
        return nothing  # Unknown result type
    end
end

