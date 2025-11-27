"""
Result I/O utilities for benchmark results.

This module provides functions to save and load benchmark results with deterministic
file naming based on parameters.
"""

using JSON3
using SHA
using Dates

"""
    BenchmarkResult

Structure to store benchmark results including timing and branching data.

# Fields
- `problem_type::String`: Type of problem (e.g., "FactoringProblem")
- `dataset_path::String`: Path to the dataset used
- `solver_name::String`: Name of the solver used
- `solver_config::Dict`: Configuration parameters of the solver
- `num_instances::Int`: Number of instances benchmarked
- `times::Vector{Float64}`: Execution time for each instance (seconds)
- `branches::Vector{Int}`: Number of branches/decisions for each instance
- `timestamp::String`: ISO 8601 timestamp when benchmark was run
- `metadata::Dict{String,Any}`: Additional metadata (e.g., Julia version, machine info)
"""
struct BenchmarkResult
    problem_type::String
    dataset_path::String
    solver_name::String
    solver_config::Dict{String,Any}
    num_instances::Int
    times::Vector{Float64}
    branches::Vector{Int}
    timestamp::String
    metadata::Dict{String,Any}
end

"""
    generate_result_filename(problem_type, dataset_path, solver_name, solver_config)

Generate a deterministic filename based on benchmark parameters using SHA256 hash.

# Returns
A filename in the format: `result_<short_hash>.json`

# Example
```julia
filename = generate_result_filename(FactoringProblem, "numbers_10x10.txt", "BI", config_dict)
# Returns something like: "result_a3f5b2c9.json"
```
"""
function generate_result_filename(problem_type::Type{<:AbstractBenchmarkProblem},
                                   dataset_path::AbstractString,
                                   solver_name::String,
                                   solver_config::Dict)
    # Create a canonical string representation of parameters
    # Use basename of dataset to make it path-independent
    dataset_basename = basename(dataset_path)
    
    # Sort config keys for deterministic hashing
    config_str = join(["$k=$(solver_config[k])" for k in sort(collect(keys(solver_config)))], ",")
    
    param_string = "$(problem_type)|$(dataset_basename)|$(solver_name)|$(config_str)"
    
    # Generate SHA256 hash and take first 8 characters for readability
    hash_value = bytes2hex(sha256(param_string))[1:8]
    
    return "$(hash_value).json"
end

"""
    solver_config_dict(solver::AbstractSolver)

Extract configuration parameters from a solver as a dictionary.
"""
function solver_config_dict(solver::BooleanInferenceSolver)
    bs = solver.bsconfig
    config = Dict{String,Any}(
        "table_solver" => string(typeof(bs.table_solver)),
        "selector_type" => string(typeof(bs.selector)),
        "measure" => string(typeof(bs.measure)),
        "set_cover_solver" => string(typeof(bs.set_cover_solver)),
        "reducer" => string(typeof(solver.reducer)),
        "show_stats" => solver.show_stats,
        "verify" => solver.verify
    )
    
    # Extract selector parameters based on type
    selector = bs.selector
    if hasfield(typeof(selector), :k)
        config["selector_k"] = selector.k
    end
    if hasfield(typeof(selector), :max_tensors)
        config["selector_max_tensors"] = selector.max_tensors
    end
    if hasfield(typeof(selector), :table_solver)
        config["selector_table_solver"] = string(typeof(selector.table_solver))
    end
    if hasfield(typeof(selector), :set_cover_solver)
        config["selector_set_cover_solver"] = string(typeof(selector.set_cover_solver))
    end
    
    return config
end

function solver_config_dict(solver::IPSolver)
    return Dict{String,Any}(
        "optimizer" => string(solver.optimizer)[1:end-10],  # Remove "Optimizer" suffix
        "verify" => solver.verify
    )
end

function solver_config_dict(solver::XSATSolver)
    return Dict{String,Any}(
        "timeout" => solver.timeout,
        "verify" => solver.verify
    )
end

function solver_config_dict(solver::CNFSolver)
    return Dict{String,Any}(
        "solver_type" => string(typeof(solver)),
        "timeout" => solver.timeout,
        "quiet" => solver.quiet,
        "verify" => solver.verify
    )
end

"""
    collect_metadata()

Collect system and environment metadata for the benchmark.
"""
function collect_metadata()
    return Dict{String,Any}(
        "julia_version" => string(VERSION),
        "hostname" => gethostname(),
        "os" => Sys.KERNEL,
        "arch" => string(Sys.ARCH),
        "cpu_threads" => Sys.CPU_THREADS,
    )
end

"""
    save_benchmark_result(result::BenchmarkResult, output_dir::String)

Save benchmark result to a JSON file with deterministic naming.
Creates subdirectories based on dataset name for better organization.

# Arguments
- `result::BenchmarkResult`: The benchmark result to save
- `output_dir::String`: Base directory where the result file will be saved

# Returns
The full path to the saved file.

# Example
```julia
result = BenchmarkResult(...)
path = save_benchmark_result(result, resolve_results_dir("factoring"))
# Saves to: results/factoring/numbers_8x8/result_xxxxxxxx.json
```
"""
function save_benchmark_result(result::BenchmarkResult, output_dir::String)
    # Extract dataset name (without extension) for subdirectory
    dataset_name = splitext(basename(result.dataset_path))[1]
    dataset_dir = joinpath(output_dir, dataset_name)
    isdir(dataset_dir) || mkpath(dataset_dir)
    
    # Reconstruct parameters for filename generation
    # Note: We need the problem type, but we only have its string name
    # So we construct filename directly from result data
    param_string = "$(result.problem_type)|$(basename(result.dataset_path))|$(result.solver_name)|$(join(["$k=$(result.solver_config[k])" for k in sort(collect(keys(result.solver_config)))], ","))"
    hash_value = bytes2hex(sha256(param_string))[1:8]
    filename = "result_$(hash_value).json"
    
    filepath = joinpath(dataset_dir, filename)
    
    # Convert to JSON-serializable format
    json_data = Dict(
        "problem_type" => result.problem_type,
        "dataset_path" => result.dataset_path,
        "solver_name" => result.solver_name,
        "solver_config" => result.solver_config,
        "num_instances" => result.num_instances,
        "times" => result.times,
        "branches" => result.branches,
        "timestamp" => result.timestamp,
        "metadata" => result.metadata
    )
    
    open(filepath, "w") do io
        JSON3.pretty(io, json_data, JSON3.AlignmentContext(indent=2))
    end
    
    @info "Benchmark result saved to: $filepath"
    return filepath
end

"""
    load_benchmark_result(filepath::String)

Load a benchmark result from a JSON file.

# Arguments
- `filepath::String`: Path to the result JSON file

# Returns
A `BenchmarkResult` object.
"""
function load_benchmark_result(filepath::String)
    json_data = JSON3.read(read(filepath, String))
    
    return BenchmarkResult(
        json_data.problem_type,
        json_data.dataset_path,
        json_data.solver_name,
        Dict{String,Any}(json_data.solver_config),
        json_data.num_instances,
        Vector{Float64}(json_data.times),
        Vector{Int}(json_data.branches),
        json_data.timestamp,
        Dict{String,Any}(json_data.metadata)
    )
end

"""
    find_result_file(problem_type, dataset_path, solver_name, solver_config, search_dir)

Find an existing result file with matching parameters.
Looks in the dataset-specific subdirectory.

# Returns
The filepath if found, otherwise `nothing`.
"""
function find_result_file(problem_type::Type{<:AbstractBenchmarkProblem},
                          dataset_path::AbstractString,
                          solver_name::String,
                          solver_config::Dict,
                          search_dir::String)
    dataset_name = splitext(basename(dataset_path))[1]
    dataset_dir = joinpath(search_dir, dataset_name)
    
    filename = generate_result_filename(problem_type, dataset_path, solver_name, solver_config)
    filepath = joinpath(dataset_dir, filename)
    
    return isfile(filepath) ? filepath : nothing
end

"""
    print_result_summary(result::BenchmarkResult)

Print a summary of benchmark results.
"""
function print_result_summary(result::BenchmarkResult)
    println("\n" * "="^70)
    println("Benchmark Result Summary")
    println("="^70)
    println("Problem Type:    $(result.problem_type)")
    println("Dataset:         $(basename(result.dataset_path))")
    println("Solver:          $(result.solver_name)")
    println("Instances:       $(result.num_instances)")
    println("Timestamp:       $(result.timestamp)")
    println("\nSolver Configuration:")
    for k in sort(collect(keys(result.solver_config)))
        println("  $k: $(result.solver_config[k])")
    end
    
    println("\nTiming Statistics:")
    println("  Mean:    $(round(mean(result.times), digits=4))s")
    println("  Median:  $(round(median(result.times), digits=4))s")
    println("  Min:     $(round(minimum(result.times), digits=4))s")
    println("  Max:     $(round(maximum(result.times), digits=4))s")
    println("  Total:   $(round(sum(result.times), digits=4))s")
    
    println("\nBranching Statistics:")
    println("  Mean:    $(round(mean(result.branches), digits=2))")
    println("  Median:  $(round(median(result.branches), digits=2))")
    println("  Min:     $(minimum(result.branches))")
    println("  Max:     $(maximum(result.branches))")
    println("  Total:   $(sum(result.branches))")
    println("="^70)
end

