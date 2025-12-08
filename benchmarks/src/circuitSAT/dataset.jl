# Dataset management for CircuitSAT benchmarks

"""
    discover_circuit_files(dir::String; format::Symbol)

Recursively discover circuit files in a directory.
- format: :verilog (*.v files) or :aag (*.aag files)
"""
function discover_circuit_files(dir::String; format::Symbol)
    format in (:verilog, :aag) || error("Format must be :verilog or :aag")
    
    extension = format == :verilog ? ".v" : ".aag"
    files = String[]
    
    for (root, dirs, filenames) in walkdir(dir)
        for filename in filenames
            if endswith(filename, extension)
                push!(files, joinpath(root, filename))
            end
        end
    end
    
    sort!(files)
    return files
end

"""
    create_circuitsat_configs(files::Vector{String}; format::Symbol)

Create CircuitSATConfig objects from a list of files.
"""
function create_circuitsat_configs(files::Vector{String}; format::Symbol)
    return [CircuitSATConfig(format, path) for path in files]
end

"""
    load_verilog_dataset(dir::String)

Load all Verilog files from a directory and create configs.
"""
function load_verilog_dataset(dir::String)
    files = discover_circuit_files(dir; format=:verilog)
    @info "Found $(length(files)) Verilog files in $dir"
    return create_circuitsat_configs(files; format=:verilog)
end

"""
    load_aag_dataset(dir::String)

Load all AAG files from a directory and create configs.
"""
function load_aag_dataset(dir::String)
    files = discover_circuit_files(dir; format=:aag)
    @info "Found $(length(files)) AAG files in $dir"
    return create_circuitsat_configs(files; format=:aag)
end

"""
    load_circuit_datasets(; verilog_dirs=String[], aag_dirs=String[])

Load circuit datasets from multiple directories.

# Example
```julia
configs = load_circuit_datasets(
    verilog_dirs=["data/iscas85"],
    aag_dirs=["data/aig/arithmetic"]
)
```
"""
function load_circuit_datasets(; verilog_dirs=String[], aag_dirs=String[])
    configs = CircuitSATConfig[]
    
    for dir in verilog_dirs
        append!(configs, load_verilog_dataset(dir))
    end
    
    for dir in aag_dirs
        append!(configs, load_aag_dataset(dir))
    end
    
    @info "Total $(length(configs)) circuit configs loaded"
    return configs
end



