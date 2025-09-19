# Generic benchmark framework using multiple dispatch

using Random
using BenchmarkTools
using JSON3
using Statistics: mean, median, std, quantile
using Dates: now

"""
    generate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                     configs::Vector{<:AbstractProblemConfig}, 
                     per_config=100, 
                     rng=Random.GLOBAL_RNG,
                     include_solution=false)

Generate datasets for a given problem type.
"""
function generate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                          configs::Vector{<:AbstractProblemConfig},
                          per_config::Int=100,
                          rng::AbstractRNG=Random.GLOBAL_RNG,
                          include_solution::Bool=false)
    
    # Get output directory based on problem type
    outdir = resolve_data_dir(lowercase(string(problem_type)[1:end-7]))  # Remove "Problem" suffix
    isdir(outdir) || mkpath(outdir)
    
    paths = String[]
    for config in configs
        filename = filename_pattern(problem_type, config)
        path = joinpath(outdir, filename)
        
        open(path, "w") do io
            for _ in 1:per_config
                instance = generate_instance(problem_type, config; rng=rng, include_solution=include_solution)
                JSON3.write(io, instance)
                write(io, '\n')
            end
        end
        
        @info "Generated dataset: $path"
        push!(paths, path)
    end
    
    @info "Generated $(length(paths)) dataset files in: $outdir"
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
        
        # Benchmark each instance once
        all_times = Float64[]
        all_memory = Int64[]
        all_gc_times = Float64[]
        successful_runs = 0
        failed_runs = 0
        
        for (i, instance) in enumerate(instances)
            try
                # Create trial function for this specific instance
                trial_fn = () -> solve_instance(problem_type, instance, solver)
                
                # Test function works (warmup)
                trial_fn()
                
                # Run benchmark
                b = @benchmarkable $trial_fn()
                tune!(b)
                result = run(b, samples=1)
                
                # Collect statistics
                push!(all_times, median(result).time / 1e9)  # Convert to seconds
                push!(all_memory, median(result).memory)
                push!(all_gc_times, median(result).gctime / 1e9)
                successful_runs += 1
                
                if i % 10 == 0 || i == length(instances)
                    @info "  Completed $i/$(length(instances)) instances"
                end
                
            catch e
                @warn "  Instance $i failed: $e"
                failed_runs += 1
            end
        end
        
        if isempty(all_times)
            return create_failed_result(config, "all_instances_failed", failed_runs)
        end
        
        # Calculate statistics
        return Dict(
            "config" => config,
            "status" => "success",
            "instances_tested" => length(instances),
            "successful_runs" => successful_runs,
            "failed_runs" => failed_runs,
            
            # Timing statistics
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
                     dataset_per_config=50)

Backend function: run complete benchmark suite using pre-generated datasets.
"""
function benchmark_backend(problem_type::Type{<:AbstractBenchmarkProblem},
                           configs::Vector{<:AbstractProblemConfig};
                           solver=nothing,
                           dataset_per_config::Int=50)
    
    problem_name = lowercase(string(problem_type)[1:end-7])  # Remove "Problem" suffix
    
    # Generate datasets
    @info "Generating $problem_name datasets..."
    generate_datasets(problem_type; configs=configs, per_config=dataset_per_config, include_solution=true)
    
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
                      configs=nothing, solver=nothing, kwargs...)

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

"""Print a nice summary of benchmark results"""
function print_benchmark_summary(results)
    println("\n" * "="^60)
    println("🏆 BENCHMARK SUMMARY")
    println("="^60)
    
    successful = filter(r -> r["status"] == "success", results)
    failed = filter(r -> r["status"] == "failed", results)
    
    if !isempty(successful)
        println("✅ Successful benchmarks: $(length(successful))")
        println("┌" * "─"^68 * "┐")
        println("│ Config      │ Median Time │ Memory      │ Instances │ Runs      │")
        println("├" * "─"^68 * "┤")
        
        for result in successful
            config = result["config"]
            median_time = result["median_time"]
            median_memory = result["median_memory"]
            instances = get(result, "instances_tested", 0)
            runs = get(result, "successful_runs", 0)
            
            config_str = "$(config.m)×$(config.n)"
            time_str = format_time(median_time)
            memory_str = format_bytes(median_memory)
            
            println("│ $(rpad(config_str, 11)) │ $(rpad(time_str, 11)) │ $(rpad(memory_str, 11)) │ $(rpad(string(instances), 9)) │ $(rpad(string(runs), 9)) │")
        end
        println("└" * "─"^68 * "┘")
    end
    
    if !isempty(failed)
        println("\n❌ Failed benchmarks: $(length(failed))")
        for result in failed
            config = result["config"]
            reason = result["reason"]
            println("  • $(config): $reason")
        end
    end
    
    println("="^60)
end

"""Format time in human-readable way"""
function format_time(seconds::Float64)
    if seconds < 1e-6
        return "$(round(seconds * 1e9, digits=1))ns"
    elseif seconds < 1e-3
        return "$(round(seconds * 1e6, digits=1))μs"
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
