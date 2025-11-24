function resolve_data_dir(parts::AbstractString...)
    base = normpath(joinpath(@__DIR__, ".."))
    dir = joinpath(base, "data", parts...)
    isdir(dir) || mkpath(dir)
    return dir
end

# Helper function for finding executables in PATH
function find_executable_in_path(cmd::String, name::String)
    try
        return strip(read(`which $cmd`, String))
    catch
        error("$name not found in PATH. Please provide explicit path or install it.")
    end
end

# Helper function for validating executable path
function validate_executable_path(path::Union{String, Nothing}, name::String)
    if isnothing(path)
        return nothing
    elseif !isfile(path)
        error("File $path for $name does not exist")
    else
        return path
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