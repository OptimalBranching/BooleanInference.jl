# Dataset management for CNF SAT benchmarks

"""
    discover_cnf_files(dir::String)

Recursively discover CNF files (*.cnf) in a directory.
"""
function discover_cnf_files(dir::String)
    files = String[]

    for (root, dirs, filenames) in walkdir(dir)
        for filename in filenames
            if endswith(filename, ".cnf")
                push!(files, joinpath(root, filename))
            end
        end
    end

    sort!(files)
    return files
end

"""
    create_cnfsat_configs(files::Vector{String})

Create CNFSATConfig objects from a list of CNF files.
"""
function create_cnfsat_configs(files::Vector{String})
    return [CNFSATConfig(path) for path in files]
end

"""
    load_cnf_dataset(dir::String)

Load all CNF files from a directory and create configs.
"""
function load_cnf_dataset(dir::String)
    files = discover_cnf_files(dir)
    @info "Found $(length(files)) CNF files in $dir"
    return create_cnfsat_configs(files)
end

"""
    load_cnf_datasets(dirs::Vector{String})

Load CNF datasets from multiple directories.

# Example
```julia
configs = load_cnf_datasets([
    "benchmarks/third-party/CnC/tests",
    "data/sat-competition"
])
```
"""
function load_cnf_datasets(dirs::Vector{String})
    configs = CNFSATConfig[]

    for dir in dirs
        if isdir(dir)
            append!(configs, load_cnf_dataset(dir))
        else
            @warn "Directory not found: $dir"
        end
    end

    @info "Total $(length(configs)) CNF configs loaded"
    return configs
end
