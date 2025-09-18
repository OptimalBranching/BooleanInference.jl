# Generic benchmark framework using multiple dispatch

using Random
using BenchmarkTools
using JSON3

"""
    generate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                     configs=default_configs(problem_type), 
                     per_config=100, 
                     rng=Random.GLOBAL_RNG,
                     include_solution=false)

Generate datasets for a given problem type.
"""
function generate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                          configs=default_configs(problem_type),
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
                     samples_per_config=5,
                     rng=Random.MersenneTwister(42))

Benchmark solving for a given problem type.
"""
function benchmark_problem(problem_type::Type{<:AbstractBenchmarkProblem}; 
                          configs=default_configs(problem_type),
                          samples_per_config::Int=5,
                          rng::AbstractRNG=Random.MersenneTwister(42))
    
    results = []
    for config in configs
        @info "Benchmarking config: $config"
        times = Float64[]
        
        for _ in 1:samples_per_config
            # Generate a random instance for this config
            instance = generate_instance(problem_type, config; rng=rng)
            
            # Benchmark solving it
            t = @belapsed solve_instance($problem_type, $instance)
            push!(times, t)
        end
        
        push!(results, Dict(
            "config" => config,
            "times" => times,
            "mean_time" => sum(times) / length(times),
            "min_time" => minimum(times)
        ))
    end
    
    return results
end

"""
    run_full_benchmark(problem_type::Type{<:AbstractBenchmarkProblem}; 
                      dataset_per_config=50, 
                      benchmark_samples=3)

Run complete benchmark suite: generate datasets and run performance benchmarks.
"""
function run_full_benchmark(problem_type::Type{<:AbstractBenchmarkProblem}; 
                           dataset_per_config::Int=50,
                           benchmark_samples::Int=3)
    
    problem_name = lowercase(string(problem_type)[1:end-7])  # Remove "Problem" suffix
    
    # Generate datasets
    @info "Generating $problem_name datasets..."
    generate_datasets(problem_type; per_config=dataset_per_config, include_solution=true)
    
    # Run benchmarks
    @info "Running $problem_name benchmarks..."
    results = benchmark_problem(problem_type; samples_per_config=benchmark_samples)
    
    # Save results
    results_path = joinpath(resolve_data_dir(), "$(problem_name)_benchmark_results.json")
    open(results_path, "w") do io
        JSON3.pretty(io, results)
    end
    @info "Benchmark results saved to: $results_path"
    
    return results
end
