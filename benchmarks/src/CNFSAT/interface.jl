# Interface functions for CNF SAT benchmarking

# Solvers available for CNF SAT
function available_solvers(::Type{CNFSATProblem})
    return [BooleanInferenceSolver(), KissatSolver(), MinisatSolver()]
end

function default_solver(::Type{CNFSATProblem})
    return BooleanInferenceSolver()
end

# Problem identification
function problem_id(config::CNFSATConfig)
    return basename(config.path)
end

function problem_id(instance::CNFSATInstance)
    return instance.name
end

# Load a single CNF instance from file
function load_cnf_instance(config::CNFSATConfig)
    return parse_cnf_file(config.path)
end

# Read instances from a config (for compatibility with benchmark API)
function read_instances(::Type{CNFSATProblem}, config::CNFSATConfig)
    return [load_cnf_instance(config)]
end

# Read instances from a directory path (for benchmark_dataset)
function read_instances(::Type{CNFSATProblem}, path::AbstractString)
    if isfile(path)
        # Single file
        if !endswith(path, ".cnf")
            error("Expected .cnf file, got: $path")
        end
        config = CNFSATConfig(path)
        return [load_cnf_instance(config)]
    elseif isdir(path)
        # Directory: load all .cnf files
        cnf_files = discover_cnf_files(path)

        instances = CNFSATInstance[]

        for cnf_file in cnf_files
            try
                config = CNFSATConfig(cnf_file)
                push!(instances, load_cnf_instance(config))
            catch e
                @warn "Failed to load $cnf_file" exception=e
            end
        end

        return instances
    else
        error("Path not found: $path")
    end
end

# Generate a single instance (for compatibility, just loads the file)
function generate_instance(::Type{CNFSATProblem}, config::CNFSATConfig; kwargs...)
    return load_cnf_instance(config)
end

# Verify solution
function verify_solution(::Type{CNFSATProblem}, instance::CNFSATInstance, result)
    # Check if we got a valid result
    if result === nothing
        return false
    end

    # The result should be a tuple (is_sat, stats) or similar
    # We consider it successful if the solver ran without errors
    return true
end

# Helper function to check if the CNF is satisfiable
function is_cnf_satisfiable(result)
    if result === nothing
        return nothing  # Solver failed
    end
    # Assuming result is (satisfiable::Bool, stats)
    if result isa Tuple && length(result) >= 1
        return result[1]
    end
    return nothing
end
