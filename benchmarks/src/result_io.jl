"""
Result I/O utilities for benchmark results.

This module provides functions to save and load benchmark results with deterministic
file naming based on parameters.
"""

using JSON3
using SHA
using Dates
using Statistics: mean, median
using Printf

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
    
    # Convert JSON3 objects to proper Dict types
    solver_config = Dict{String,Any}()
    for (k, v) in pairs(json_data.solver_config)
        solver_config[string(k)] = v
    end
    
    metadata = Dict{String,Any}()
    for (k, v) in pairs(json_data.metadata)
        metadata[string(k)] = v
    end
    
    return BenchmarkResult(
        string(json_data.problem_type),
        string(json_data.dataset_path),
        string(json_data.solver_name),
        solver_config,
        Int(json_data.num_instances),
        Vector{Float64}(json_data.times),
        Vector{Int}(json_data.branches),
        string(json_data.timestamp),
        metadata
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
    load_all_results(problem_dir::String)

Load all result files from a problem directory (e.g., results/factoring/).
Returns a vector of BenchmarkResult objects.

# Example
```julia
results = load_all_results(resolve_results_dir("factoring"))
```
"""
function load_all_results(problem_dir::String)
    results = BenchmarkResult[]
    
    if !isdir(problem_dir)
        @warn "Directory not found: $problem_dir"
        return results
    end
    
    for dataset_dir in readdir(problem_dir, join=true)
        isdir(dataset_dir) || continue
        
        for file in readdir(dataset_dir, join=true)
            if endswith(file, ".json")
                try
                    push!(results, load_benchmark_result(file))
                catch e
                    @warn "Failed to load $file: $e"
                end
            end
        end
    end
    
    return results
end

"""
    load_dataset_results(problem_dir::String, dataset_name::String)

Load all results for a specific dataset.

# Example
```julia
results = load_dataset_results(resolve_results_dir("factoring"), "numbers_8x8")
```
"""
function load_dataset_results(problem_dir::String, dataset_name::String)
    results = BenchmarkResult[]
    dataset_dir = joinpath(problem_dir, dataset_name)
    
    if !isdir(dataset_dir)
        @warn "Dataset directory not found: $dataset_dir"
        return results
    end
    
    for file in readdir(dataset_dir, join=true)
        if endswith(file, ".json")
            try
                push!(results, load_benchmark_result(file))
            catch e
                @warn "Failed to load $file: $e"
            end
        end
    end
    
    return results
end

"""
    get_config_summary(result::BenchmarkResult)

Generate a short summary string for the solver configuration.
"""
function get_config_summary(result::BenchmarkResult)
    config = result.solver_config
    
    # Abbreviation mappings
    selector_abbrev = Dict(
        "MostOccurrenceSelector" => "MostOcc",
        "LeastOccurrenceSelector" => "LeastOcc",
        "MinGammaSelector" => "MinGamma"
    )
    
    measure_abbrev = Dict(
        "NumHardTensors" => "HardT",
        "NumUnfixedVars" => "UnfixV",
        "NumUnfixedTensors" => "UnfixT",
        "HardSetSize" => "HardSet"
    )
    
    if result.solver_name == "BI"
        parts = String[]
        
        # Selector info
        if haskey(config, "selector_type")
            selector = split(string(config["selector_type"]), ".")[end]  # Get last part after dot
            selector_short = get(selector_abbrev, selector, selector)
            
            if haskey(config, "selector_k") && haskey(config, "selector_max_tensors")
                push!(parts, "$(selector_short)($(config["selector_k"]),$(config["selector_max_tensors"]))")
            else
                push!(parts, selector_short)
            end
        end
        
        # Measure info
        if haskey(config, "measure")
            measure = split(string(config["measure"]), ".")[end]
            measure_short = get(measure_abbrev, measure, measure)
            push!(parts, measure_short)
        end
        
        return join(parts, "+")
    else
        # For non-BI solvers, just return solver type
        return result.solver_name
    end
end

"""
    compare_results(results::Vector{BenchmarkResult})

Compare multiple benchmark results and print a comparison table.
"""
function compare_results(results::Vector{BenchmarkResult})
    isempty(results) && (@warn "No results to compare"; return)
    
    println("\n" * "="^100)
    println("Benchmark Results Comparison")
    println("="^100)
    
    # Group by dataset
    datasets = unique([splitext(basename(r.dataset_path))[1] for r in results])
    
    for dataset in sort(datasets)
        dataset_results = filter(r -> splitext(basename(r.dataset_path))[1] == dataset, results)
        isempty(dataset_results) && continue
        
        println("\nDataset: $dataset")
        println("-"^100)
        println(@sprintf("%-14s %-19s %12s %12s %12s %12s %8s", 
                        "Solver", "Config", "Mean Time", "Total Time", "Mean Branch", "Total Branch", "N"))
        println("-"^100)
        
        for result in sort(dataset_results, by=r->mean(r.times))
            config_str = get_config_summary(result)
            
            mean_time = mean(result.times)
            total_time = sum(result.times)
            
            if !all(iszero, result.branches)
                mean_branch = mean(result.branches)
                total_branch = sum(result.branches)
                println(@sprintf("%-14s %-19s %12.4f %12.4f %12.2f %12d %8d", 
                                result.solver_name, config_str[1:min(25,end)], 
                                mean_time, total_time, mean_branch, total_branch, result.num_instances))
            else
                println(@sprintf("%-14s %-19s %12.4f %12.4f %12s %12s %8d", 
                                result.solver_name, config_str[1:min(25,end)], 
                                mean_time, total_time, "-", "-", result.num_instances))
            end
        end
    end
    println("="^100)
end

"""
    filter_results(results::Vector{BenchmarkResult}; solver_name=nothing, dataset=nothing)

Filter results by solver name and/or dataset.
"""
function filter_results(results::Vector{BenchmarkResult}; 
                       solver_name::Union{String,Nothing}=nothing,
                       dataset::Union{String,Nothing}=nothing)
    filtered = results
    
    if !isnothing(solver_name)
        filtered = filter(r -> r.solver_name == solver_name, filtered)
    end
    
    if !isnothing(dataset)
        filtered = filter(r -> splitext(basename(r.dataset_path))[1] == dataset, filtered)
    end
    
    return filtered
end

"""
    print_detailed_comparison(results::Vector{BenchmarkResult})

Print a detailed comparison showing all configuration parameters.
"""
function print_detailed_comparison(results::Vector{BenchmarkResult})
    isempty(results) && (@warn "No results to compare"; return)
    
    println("\n" * "="^100)
    println("Detailed Configuration Comparison")
    println("="^100)
    
    for (i, result) in enumerate(results)
        println("\n[$i] $(result.solver_name) - $(basename(result.dataset_path))")
        println("  Mean Time:   $(round(mean(result.times), digits=4))s")
        println("  Total Time:  $(round(sum(result.times), digits=4))s")
        
        if !all(iszero, result.branches)
            println("  Mean Branch: $(round(mean(result.branches), digits=2))")
            println("  Total Branch: $(sum(result.branches))")
        end
        
        println("  Configuration:")
        for k in sort(collect(keys(result.solver_config)))
            println("    $k: $(result.solver_config[k])")
        end
    end
    println("="^100)
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
    
    # Only print branching statistics if they exist (not all zeros)
    if !all(iszero, result.branches)
        println("\nBranching Statistics:")
        println("  Mean:    $(round(mean(result.branches), digits=2))")
        println("  Median:  $(round(median(result.branches), digits=2))")
        println("  Min:     $(minimum(result.branches))")
        println("  Max:     $(maximum(result.branches))")
        println("  Total:   $(sum(result.branches))")
    end
    println("="^70)
end

