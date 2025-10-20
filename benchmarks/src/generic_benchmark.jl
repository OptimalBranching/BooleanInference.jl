# Generic benchmark framework using multiple dispatch

"""
    dataset_metadata_hash(problem_type, config, per_config, seed, include_solution)

Generate a stable hash for dataset parameters to enable caching and reproducibility.
"""
function dataset_metadata_hash(problem_type::Type{<:AbstractBenchmarkProblem}, 
                               config::AbstractProblemConfig,
                               per_config::Int, 
                               seed::UInt64,
                               include_solution::Bool)
    # Create a deterministic string representation of all parameters
    parts = [
        string(problem_type),
        string(config),
        string(per_config),
        string(seed),
        string(include_solution)
    ]
    content = join(parts, "|")
    return bytes2hex(sha256(content))[1:16]  # 16-char prefix
end

"""
    deterministic_seed(problem_type, config)

Generate a deterministic seed for reproducible dataset generation.
"""
function deterministic_seed(problem_type::Type{<:AbstractBenchmarkProblem}, 
                           config::AbstractProblemConfig)
    # Create deterministic seed from problem type and config
    content = string(problem_type) * "|" * string(config)
    hash_bytes = sha256(content)
    # Convert first 8 bytes to UInt64 for seed
    return reinterpret(UInt64, hash_bytes[1:8])[1]
end

"""
    check_dataset_compatibility(dataset_path, problem_type, config, per_config, seed, include_solution)

Check if existing dataset is compatible with current parameters.
"""
function check_dataset_compatibility(dataset_path::String,
                                   problem_type::Type{<:AbstractBenchmarkProblem},
                                   config::AbstractProblemConfig,
                                   per_config::Int,
                                   seed::UInt64,
                                   include_solution::Bool)
    if !isfile(dataset_path)
        return false
    end
    
    try
        # Read first line to get metadata
        lines = readlines(dataset_path)
        if isempty(lines)
            return false
        end
        
        # Check if we have the expected number of lines
        if length(lines) != per_config
            @info "  Dataset size mismatch: expected $per_config instances, found $(length(lines))"
            return false
        end
        
        # Try to parse first instance and check if it has metadata
        first_instance = JSON3.read(lines[1])
        expected_hash = dataset_metadata_hash(problem_type, config, per_config, seed, include_solution)
        
        # Check if instance has metadata hash
        if haskey(first_instance, "_metadata_hash")
            if first_instance["_metadata_hash"] == expected_hash
                @info "  Found compatible dataset: $dataset_path"
                return true
            else
                @info "  Dataset parameter mismatch: $dataset_path"
                return false
            end
        else
            # Legacy dataset without metadata - consider incompatible
            @info "  Legacy dataset without metadata: $dataset_path"
            return false
        end
    catch e
        @warn "  Error checking dataset compatibility: $e"
        return false
    end
end

"""
    generate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                     configs::Vector{<:AbstractProblemConfig}, 
                     per_config=100, 
                     include_solution=false,
                     force_regenerate=false)

Generate datasets for a given problem type with reproducible, cached results.
If datasets already exist with compatible parameters, they will be reused.
Uses deterministic seeding for reproducibility - no external RNG needed.
"""
function generate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                          configs::Vector{<:AbstractProblemConfig},
                          per_config::Int=100,
                          include_solution::Bool=false,
                          force_regenerate::Bool=false)
    
    # Get output directory based on problem type
    outdir = resolve_data_dir(lowercase(string(problem_type)[1:end-7]))  # Remove "Problem" suffix
    isdir(outdir) || mkpath(outdir)
    
    paths = String[]
    generated_count = 0
    reused_count = 0
    
    for config in configs
        filename = filename_pattern(problem_type, config)
        path = joinpath(outdir, filename)
        
        # Generate deterministic seed for reproducibility
        seed = deterministic_seed(problem_type, config)
        
        # Check if compatible dataset already exists
        if !force_regenerate && check_dataset_compatibility(path, problem_type, config, per_config, seed, include_solution)
            @info "Reusing existing dataset: $path"
            push!(paths, path)
            reused_count += 1
            continue
        end
        
        @info "Generating new dataset: $path"
        @info "  Using deterministic seed: $seed"
        
        # Create seeded RNG for reproducible generation
        seeded_rng = Random.Xoshiro(seed)
        metadata_hash = dataset_metadata_hash(problem_type, config, per_config, seed, include_solution)
        
        open(path, "w") do io
            for i in 1:per_config
                instance = generate_instance(problem_type, config; rng=seeded_rng, include_solution=include_solution)
                
                # Add metadata to first instance
                if i == 1
                    instance = merge(instance, Dict(
                        "_metadata_hash" => metadata_hash,
                        "_generation_seed" => seed,
                        "_generation_timestamp" => string(now())
                    ))
                end
                
                JSON3.write(io, instance)
                write(io, '\n')
            end
        end
        
        @info "Generated dataset: $path (metadata hash: $metadata_hash)"
        push!(paths, path)
        generated_count += 1
    end
    
    @info "Dataset generation complete: $(generated_count) generated, $(reused_count) reused in: $outdir"
    return paths
end

"""
    benchmark_problem(problem_type::Type{<:AbstractBenchmarkProblem}; 
                     configs=default_configs(problem_type),
                     solver=nothing)

Simple and direct benchmark using pre-generated datasets.
"""
function benchmark_problem(problem_type::Type{<:AbstractBenchmarkProblem}; 
                          configs=default_configs(problem_type),
                          solver=nothing)
    
    results = []
    
    # Use specified solver or default
    actual_solver = isnothing(solver) ? default_solver(problem_type) : solver
    solver_info = solver_name(actual_solver)
    
    @info "Using solver: $solver_info"
    
    for config in configs
        @info "Benchmarking config: $config"
        
        # Load instances from dataset
        result = benchmark_dataset_instances(problem_type, config, actual_solver, solver_info)
        push!(results, result)
    end
    
    return results
end

"""
    benchmark_dataset_instances(problem_type, config, solver, solver_info)

Benchmark using all instances from pre-generated dataset.
"""
function benchmark_dataset_instances(problem_type::Type{<:AbstractBenchmarkProblem}, 
                                    config::AbstractProblemConfig,
                                    solver,
                                    solver_info::String)
    try
        # Load instances from dataset file
        problem_name = lowercase(string(problem_type)[1:end-7])  # Remove "Problem" suffix
        filename = filename_pattern(problem_type, config)
        dataset_path = joinpath(resolve_data_dir(problem_name), filename)
        
        if !isfile(dataset_path)
            @error "Dataset file not found: $dataset_path"
            return create_failed_result(config, "dataset_not_found: $dataset_path")
        end
        
        @info "  Loading instances from: $dataset_path"
        instances = read_jsonl(dataset_path)
        @info "  Testing $(length(instances)) instances"
        
        if isempty(instances)
            @error "  No instances found in dataset file"
            return create_failed_result(config, "empty_dataset")
        end
        
        # Benchmark each instance once
        all_times = Float64[]
        all_memory = Int64[]
        all_gc_times = Float64[]
        successful_runs = 0
        failed_runs = 0
        
        # Pre-tune benchmark once for all instances to save time
        sample_trial_fn = () -> solve_instance(problem_type, instances[1], solver)
        b = @benchmarkable $sample_trial_fn()
        tune!(b)
        @info "  Benchmark tuned, starting verification and timing..."
        
        correct_runs = 0
        incorrect_runs = 0
        
        for (i, instance) in enumerate(instances)
            try
                # First, verify solution correctness (without timing)
                result = solve_instance(problem_type, instance, solver)
                is_correct = verify_solution(problem_type, instance, result)
                
                if !is_correct
                    @warn "  Instance $i: Incorrect solution, skipping timing"
                    incorrect_runs += 1
                    continue
                end
                
                correct_runs += 1
                
                # Only time correct solutions
                trial_fn = () -> solve_instance(problem_type, instance, solver)
                b_instance = @benchmarkable $trial_fn()
                # Use pre-tuned parameters
                b_instance.params = b.params
                timing_result = run(b_instance, samples=1)
                
                # Collect statistics
                push!(all_times, median(timing_result).time / 1e9)  # Convert to seconds
                push!(all_memory, median(timing_result).memory)
                push!(all_gc_times, median(timing_result).gctime / 1e9)
                successful_runs += 1
                
                if i % 10 == 0 || i == length(instances)
                    @info "  Completed $i/$(length(instances)) instances ($(correct_runs) correct, $(incorrect_runs) incorrect)"
                end
                
            catch e
                @warn "  Instance $i failed with error: $e"
                failed_runs += 1
            end
        end
        
        if isempty(all_times)
            return create_failed_result(config, "all_instances_failed: $failed_runs errors, $incorrect_runs incorrect", 
                                      failed_runs + incorrect_runs)
        end
        
        # Calculate statistics
        return Dict(
            "config" => config,
            "status" => "success",
            "instances_tested" => length(instances),
            "successful_runs" => successful_runs,
            "correct_runs" => correct_runs,
            "incorrect_runs" => incorrect_runs,
            "failed_runs" => failed_runs,
            "accuracy_rate" => correct_runs / length(instances),
            
            # Timing statistics (only for correct solutions)
            "mean_time" => mean(all_times),
            "median_time" => median(all_times),
            "min_time" => minimum(all_times),
            "max_time" => maximum(all_times),
            "std_time" => std(all_times),
            "q25_time" => quantile(all_times, 0.25),
            "q75_time" => quantile(all_times, 0.75),
            
            # Memory statistics
            "mean_memory" => mean(all_memory),
            "median_memory" => median(all_memory),
            
            # GC statistics
            "mean_gc_time" => mean(all_gc_times),
            "total_gc_time" => sum(all_gc_times),
            "gc_percentage" => 100 * sum(all_gc_times) / sum(all_times)
        )
        
    catch e
        @error "  Benchmark failed: $e"
        return create_failed_result(config, "benchmark_failed: $e")
    end
end

 


"""Create result dict for failed benchmark"""
function create_failed_result(config, reason, failed_runs=0)
    return Dict(
        "config" => config,
        "status" => "failed",
        "reason" => reason,
        "samples" => 0,
        "failed_runs" => failed_runs
    )
end

 

"""Format bytes in human-readable way"""
function format_bytes(bytes::Number)
    if bytes < 1024
        return "$(Int(bytes))B"
    elseif bytes < 1024^2
        return "$(round(bytes/1024, digits=1))KB"
    elseif bytes < 1024^3
        return "$(round(bytes/1024^2, digits=1))MB"
    else
        return "$(round(bytes/1024^3, digits=1))GB"
    end
end

"""
    benchmark_backend(problem_type::Type{<:AbstractBenchmarkProblem}, 
                     configs::Vector{<:AbstractProblemConfig};
                     solver=nothing,
                     dataset_per_config=50,
                     force_regenerate_datasets=false)

Run complete benchmark suite using pre-generated datasets.
"""
function benchmark_backend(problem_type::Type{<:AbstractBenchmarkProblem},
                           configs::Vector{<:AbstractProblemConfig};
                           solver=nothing,
                           dataset_per_config::Int=50,
                           force_regenerate_datasets::Bool=false)
    
    problem_name = lowercase(string(problem_type)[1:end-7])  # Remove "Problem" suffix
    
    # Generate datasets
    @info "Preparing $problem_name datasets..."
    generate_datasets(problem_type; 
                     configs=configs, 
                     per_config=dataset_per_config, 
                     include_solution=true,
                     force_regenerate=force_regenerate_datasets)
    
    # Run benchmarks using dataset instances
    @info "Running $problem_name benchmarks..."
    results = benchmark_problem(problem_type; 
                               configs=configs,
                               solver=solver)
    
    # Save results with enhanced information
    results_path = joinpath(resolve_data_dir(), "$(problem_name)_benchmark_results.json")
    open(results_path, "w") do io
        # Get solver info for results
        actual_solver = isnothing(solver) ? default_solver(problem_type) : solver
        solver_info = solver_name(actual_solver)
        
        enhanced_results = Dict(
            "benchmark_info" => Dict(
                "problem_type" => string(problem_type),
                "solver" => solver_info,
                "timestamp" => string(now()),
                "dataset_per_config" => dataset_per_config,
                "force_regenerate_datasets" => force_regenerate_datasets,
                "julia_version" => string(VERSION)
            ),
            "results" => results
        )
        JSON3.pretty(io, enhanced_results)
    end
    @info "Benchmark results saved to: $results_path"
    
    # Print summary
    print_benchmark_summary(results)
    
    return results
end

"""
    run_full_benchmark(problem_type::Type{<:AbstractBenchmarkProblem}, 
                      config_tuples::Vector{<:Tuple};
                      solver=nothing, kwargs...)

High-level interface: run benchmark with tuple configs (e.g., [(10,10), (12,12)]).
"""
function run_full_benchmark(problem_type::Type{<:AbstractBenchmarkProblem}, 
                           config_tuples::Vector{<:Tuple}; 
                           solver=nothing, kwargs...)
    configs = create_configs_from_tuples(problem_type, config_tuples)
    return benchmark_backend(problem_type, configs; solver=solver, kwargs...)
end

"""
    run_full_benchmark(problem_type::Type{<:AbstractBenchmarkProblem}; 
                      solver=nothing, force_regenerate_datasets=false, kwargs...)

High-level interface: run benchmark with optional configs (uses defaults if nothing).
"""
function run_full_benchmark(problem_type::Type{<:AbstractBenchmarkProblem}; 
                           solver=nothing,
                           kwargs...)
    configs = default_configs(problem_type)
    return benchmark_backend(problem_type, configs; solver=solver, kwargs...)
end

"""Create config objects from tuples"""
function create_configs_from_tuples(problem_type::Type{<:AbstractBenchmarkProblem}, tuples)
    return [config(problem_type, tuple) for tuple in tuples]
end

"""
    regenerate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                       configs=nothing, per_config=100, include_solution=true)

Force regeneration of datasets for a problem type, ignoring existing cache.
"""
function regenerate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                           configs::Union{Vector{<:AbstractProblemConfig}, Nothing}=nothing,
                           per_config::Int=100,
                           include_solution::Bool=true)
    actual_configs = isnothing(configs) ? default_configs(problem_type) : configs
    return generate_datasets(problem_type; 
                           configs=actual_configs,
                           per_config=per_config,
                           include_solution=include_solution,
                           force_regenerate=true)
end

"""Print a nice summary of benchmark results"""
function print_benchmark_summary(results)
    println("\n" * repeat("=", 60))
    println("BENCHMARK SUMMARY")
    println(repeat("=", 60))
    
    successful = filter(r -> r["status"] == "success", results)
    failed = filter(r -> r["status"] == "failed", results)
    
    if !isempty(successful)
        println("Successful benchmarks: $(length(successful))")
        println(repeat("+", 90))
        println("| Config      | Median Time | Memory      | Instances | Correct | Accuracy | Timed |")
        println(repeat("-", 90))
        
        for result in successful
            config = result["config"]
            median_time = result["median_time"]
            median_memory = result["median_memory"]
            instances = get(result, "instances_tested", 0)
            correct = get(result, "correct_runs", 0)
            accuracy = get(result, "accuracy_rate", 0.0)
            timed = get(result, "successful_runs", 0)
            
            config_str = "$(config.m)x$(config.n)"
            time_str = format_time(median_time)
            memory_str = format_bytes(median_memory)
            accuracy_str = "$(round(accuracy * 100, digits=1))%"
            
            println("| $(rpad(config_str, 11)) | $(rpad(time_str, 11)) | $(rpad(memory_str, 11)) | $(rpad(string(instances), 9)) | $(rpad(string(correct), 7)) | $(rpad(accuracy_str, 8)) | $(rpad(string(timed), 5)) |")
        end
        println(repeat("+", 90))
    end
    
    if !isempty(failed)
        println("\nFailed benchmarks: $(length(failed))")
        for result in failed
            config = result["config"]
            reason = result["reason"]
            println("  - $(config): $reason")
        end
    end
    println(repeat("=", 60))
end

"""Format time in human-readable way"""
function format_time(seconds::Float64)
    if seconds < 1e-6
        return "$(round(seconds * 1e9, digits=1))ns"
    elseif seconds < 1e-3
        return "$(round(seconds * 1e6, digits=1))us"
    elseif seconds < 1
        return "$(round(seconds * 1e3, digits=1))ms"
    elseif seconds < 60
        return "$(round(seconds, digits=2))s"
    else
        minutes = floor(seconds / 60)
        secs = seconds - minutes * 60
        return "$(Int(minutes))m$(round(secs, digits=1))s"
    end
end

"""
    list_available_solvers(problem_type::Type{<:AbstractBenchmarkProblem})

Display available solvers for a problem type.
"""
function list_available_solvers(problem_type::Type{<:AbstractBenchmarkProblem})
    solvers = available_solvers(problem_type)
    default = default_solver(problem_type)
    default_name = solver_name(default)
    
    println("Available solvers for $(string(problem_type)):")
    for solver in solvers
        name = solver_name(solver)
        is_default = name == default_name ? " (default)" : ""
        println("  • $name$is_default")
    end
end

"""
    run_solver_comparison(problem_type::Type{<:AbstractBenchmarkProblem}, config_tuples; kwargs...)

Compare all available solvers on the same problem configurations.
"""
function run_solver_comparison(problem_type::Type{<:AbstractBenchmarkProblem}, 
                               config_tuples::Vector{<:Tuple}; kwargs...)
    solvers = available_solvers(problem_type)
    results = Dict()
    
    for solver in solvers
        solver_name_str = solver_name(solver)
        @info "Running benchmark with solver: $solver_name_str"
        results[solver_name_str] = run_full_benchmark(problem_type, config_tuples; solver=solver, kwargs...)
    end
    
    return results
end

"""
    save_solver_comparison(problem_type::Type{<:AbstractBenchmarkProblem}, solver_results::Dict; note="")

Persist solver comparison results to JSON under the benchmark data directory.
Includes benchmark metadata (timestamp, Julia version) and optional note.
"""
function save_solver_comparison(problem_type::Type{<:AbstractBenchmarkProblem}, solver_results::Dict; note::AbstractString="")
    if isempty(solver_results)
        @warn "No solver results to save. Skipping."
        return nothing
    end

    # Determine problem name and output path
    problem_name = lowercase(string(problem_type)[1:end-7])  # Remove "Problem" suffix
    results_path = joinpath(resolve_data_dir(), "$(problem_name)_solver_comparison.json")

    # Extract common configs from the first solver
    first_results = first(values(solver_results))
    configs = [result["config"] for result in first_results if haskey(result, "config")]

    # Build a normalized structure for saving
    payload = Dict(
        "benchmark_info" => Dict(
            "problem_type" => string(problem_type),
            "timestamp" => string(now()),
            "julia_version" => string(VERSION),
            "note" => note,
            "configs" => [Dict("m"=>c.m, "n"=>c.n) for c in configs]
        ),
        "solvers" => Dict(
            (name => solver_results[name]) for name in keys(solver_results)
        )
    )

    open(results_path, "w") do io
        JSON3.pretty(io, payload)
    end
    @info "Solver comparison saved to: $results_path"
    return results_path
end

"""
    print_solver_comparison_summary(solver_results::Dict)

Print a comprehensive comparison table of all solver results.
"""
function print_solver_comparison_summary(solver_results::Dict)
    if isempty(solver_results)
        println("No solver results to compare!")
        return
    end
    
    println("\n" * repeat("=", 80))
    println("SOLVER COMPARISON SUMMARY")
    println(repeat("=", 80))
    
    # Get all configs from first solver (assuming all solvers tested same configs)
    first_results = first(values(solver_results))
    configs = [result["config"] for result in first_results if result["status"] == "success"]
    
    if isempty(configs)
        println("No successful results to compare!")
        return
    end
    
    # Print header
    solver_names = collect(keys(solver_results))
    header = "| Config   "
    for solver in solver_names
        header *= "| $(rpad(solver, 15)) "
    end
    header *= "|"
    
    println(repeat("+", length(header)))
    println(header)
    println(repeat("-", length(header)))
    
    # Print results for each config
    for config in configs
        config_str = "$(config.m)x$(config.n)"
        row = "| $(rpad(config_str, 8)) "
        
        for solver in solver_names
            solver_result = solver_results[solver]
            # Find result for this config
            matching_result = nothing
            for result in solver_result
                if result["config"] == config && result["status"] == "success"
                    matching_result = result
                    break
                end
            end
            
            if isnothing(matching_result)
                time_str = "FAILED"
            else
                median_time = matching_result["median_time"]
                time_str = format_time(median_time)
            end
            row *= "| $(rpad(time_str, 15)) "
        end
        row *= "|"
        println(row)
    end
    println(repeat("+", length(header)))
    
    # Print winner analysis with accuracy information
    println("\nPerformance winners by configuration (with accuracy):")
    for config in configs
        config_str = "$(config.m)x$(config.n)"
        times = Dict{String, Float64}()
        accuracies = Dict{String, Float64}()
        
        for solver in solver_names
            solver_result = solver_results[solver]
            for result in solver_result
                if result["config"] == config && result["status"] == "success"
                    times[solver] = result["median_time"]
                    accuracies[solver] = get(result, "accuracy_rate", 0.0)
                    break
                end
            end
        end
        
        if !isempty(times)
            # Only consider solvers with perfect accuracy for performance comparison
            perfect_solvers = filter(kv -> accuracies[kv[1]] == 1.0, times)
            
            if !isempty(perfect_solvers)
                winner = argmin(perfect_solvers)
                winner_time = perfect_solvers[winner]
                println("  - $config_str: winner $winner ($(format_time(winner_time)), 100% accuracy)")
                
                # Show relative performance for perfect solvers
                sorted_perfect = sort(collect(perfect_solvers), by=x->x[2])
                if length(sorted_perfect) > 1
                    for (i, (solver, time)) in enumerate(sorted_perfect[2:end])
                        speedup = time / winner_time
                        println("    - $solver: $(round(speedup, digits=2))x slower (100% accuracy)")
                    end
                end
                
                # Show imperfect solvers separately
                imperfect_solvers = filter(kv -> accuracies[kv[1]] < 1.0, times)
                for (solver, time) in imperfect_solvers
                    accuracy_pct = round(accuracies[solver] * 100, digits=1)
                    println("    - $solver: $(format_time(time)) ($(accuracy_pct)% accuracy)")
                end
            else
                println("  - $config_str: no solver achieved 100% accuracy")
                for (solver, time) in sort(collect(times), by=x->x[2])
                    accuracy_pct = round(accuracies[solver] * 100, digits=1)
                    println("    $(solver): $(format_time(time)) ($(accuracy_pct)% accuracy)")
                end
            end
        end
    end
    println(repeat("=", 80))
end

"""
    save_benchmark_results(problem_type::Type{<:AbstractBenchmarkProblem}, results; solver=nothing, dataset_per_config=nothing, force_regenerate_datasets=nothing)

Persist single-solver benchmark results to JSON, mirroring benchmark_backend output.
"""
function save_benchmark_results(problem_type::Type{<:AbstractBenchmarkProblem}, results;
                               solver=nothing,
                               dataset_per_config=nothing,
                               force_regenerate_datasets=nothing)
    problem_name = lowercase(string(problem_type)[1:end-7])
    results_path = joinpath(resolve_data_dir(), "$(problem_name)_benchmark_results.json")

    actual_solver = isnothing(solver) ? default_solver(problem_type) : solver
    solver_info = solver_name(actual_solver)

    payload = Dict(
        "benchmark_info" => Dict(
            "problem_type" => string(problem_type),
            "solver" => solver_info,
            "timestamp" => string(now()),
            "dataset_per_config" => dataset_per_config,
            "force_regenerate_datasets" => force_regenerate_datasets,
            "julia_version" => string(VERSION)
        ),
        "results" => results
    )

    open(results_path, "w") do io
        JSON3.pretty(io, payload)
    end
    @info "Benchmark results saved to: $results_path"
    return results_path
end

"""
    compare_solver_results(name1, results1, name2, results2)

Compare two specific solver results side by side with accuracy information.
"""
function compare_solver_results(name1::String, results1, name2::String, results2)
    println(repeat("+", 98))
    println("| $(rpad("Config", 8)) | $(rpad("$name1 Time", 13)) | $(rpad("$name1 Acc", 10)) | $(rpad("$name2 Time", 13)) | $(rpad("$name2 Acc", 10)) | $(rpad("Winner", 18)) |")
    println(repeat("-", 98))
    
    # Get successful results from both solvers
    success1 = filter(r -> r["status"] == "success", results1)
    success2 = filter(r -> r["status"] == "success", results2)
    
    # Match configs
    for r1 in success1
        config = r1["config"]
        config_str = "$(config.m)x$(config.n)"
        
        # Find matching config in results2
        r2 = findfirst(r -> r["config"] == config, success2)
        if !isnothing(r2)
            r2 = success2[r2]
            
            time1 = r1["median_time"] 
            time2 = r2["median_time"]
            time1_str = format_time(time1)
            time2_str = format_time(time2)
            
            acc1 = get(r1, "accuracy_rate", 0.0)
            acc2 = get(r2, "accuracy_rate", 0.0) 
            acc1_str = "$(round(acc1 * 100, digits=1))%"
            acc2_str = "$(round(acc2 * 100, digits=1))%"
            
            # Determine winner considering both speed and accuracy
            if acc1 == 1.0 && acc2 == 1.0
                # Both perfect accuracy - compare speed
                if time1 < time2
                    winner_str = "$name1 ($(round(time2/time1, digits=2))x faster)"
                elseif time2 < time1
                    winner_str = "$name2 ($(round(time1/time2, digits=2))x faster)"
                else
                    winner_str = "Tie"
                end
            elseif acc1 == 1.0 && acc2 < 1.0
                winner_str = "$name1 (100% acc)"
            elseif acc1 < 1.0 && acc2 == 1.0
                winner_str = "$name2 (100% acc)"
            else
                # Neither has perfect accuracy - compare accuracy first, then speed
                if acc1 > acc2
                    winner_str = "$name1 (better acc)"
                elseif acc2 > acc1
                    winner_str = "$name2 (better acc)"
                else
                    # Same accuracy - compare speed
                    if time1 < time2
                        winner_str = "$name1 (faster)"
                    elseif time2 < time1
                        winner_str = "$name2 (faster)"
                    else
                        winner_str = "Tie"
                    end
                end
            end
            
            println("| $(rpad(config_str, 8)) | $(rpad(time1_str, 13)) | $(rpad(acc1_str, 10)) | $(rpad(time2_str, 13)) | $(rpad(acc2_str, 10)) | $(rpad(winner_str, 18)) |")
        else
            acc1 = get(r1, "accuracy_rate", 0.0)
            acc1_str = "$(round(acc1 * 100, digits=1))%"
            println("| $(rpad(config_str, 8)) | $(rpad(format_time(r1["median_time"]), 13)) | $(rpad(acc1_str, 10)) | $(rpad("FAILED", 13)) | $(rpad("N/A", 10)) | $(rpad(name1, 18)) |")
        end
    end
    
    # Check for configs only in results2
    for r2 in success2
        config = r2["config"]
        if !any(r -> r["config"] == config, success1)
            config_str = "$(config.m)x$(config.n)"
            acc2 = get(r2, "accuracy_rate", 0.0)
            acc2_str = "$(round(acc2 * 100, digits=1))%"
            println("| $(rpad(config_str, 8)) | $(rpad("FAILED", 13)) | $(rpad("N/A", 10)) | $(rpad(format_time(r2["median_time"]), 13)) | $(rpad(acc2_str, 10)) | $(rpad(name2, 18)) |")
        end
    end
    println(repeat("+", 98))
end
