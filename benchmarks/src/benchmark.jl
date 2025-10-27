function benchmark_problem(problem_type::Type{<:AbstractBenchmarkProblem}; 
                          configs=default_configs(problem_type),
                          solver=nothing)
    
    results = []
    actual_solver = isnothing(solver) ? default_solver(problem_type) : solver
    solver_info = solver_name(actual_solver)
    
    @info "Using solver: $solver_info"
    
    for config in configs
        @info "Benchmarking config: $config"
        result = benchmark_dataset_instances(problem_type, config, actual_solver, solver_info)
        push!(results, result)
    end
    
    return results
end

function benchmark_dataset_instances(problem_type::Type{<:AbstractBenchmarkProblem}, 
                                    config::AbstractProblemConfig,
                                    solver,
                                    solver_info::String)
    try
        problem_name = lowercase(string(problem_type)[1:end-7])
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
        
        all_times = Float64[]
        all_memory = Int64[]
        all_gc_times = Float64[]
        successful_runs = 0
        failed_runs = 0
        
        sample_trial_fn = () -> solve_instance(problem_type, instances[1], solver)
        b = @benchmarkable $sample_trial_fn()
        tune!(b)
        @info "  Benchmark tuned, starting verification and timing..."
        
        correct_runs = 0
        incorrect_runs = 0
        
        for (i, instance) in enumerate(instances)
            try
                result = solve_instance(problem_type, instance, solver)
                is_correct = verify_solution(problem_type, instance, result)
                
                if !is_correct
                    @warn "  Instance $i: Incorrect solution"
                    incorrect_runs += 1
                    continue
                end
                
                correct_runs += 1
                
                trial_fn = () -> solve_instance(problem_type, instance, solver)
                b_instance = @benchmarkable $trial_fn()
                b_instance.params = b.params
                timing_result = run(b_instance, samples=1)
                
                push!(all_times, median(timing_result).time / 1e9)
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
        
        return Dict(
            "config" => config,
            "status" => "success",
            "instances_tested" => length(instances),
            "correct_runs" => correct_runs,
            "successful_runs" => successful_runs,
            "accuracy_rate" => correct_runs / length(instances),
            "median_time" => median(all_times),
            "median_memory" => median(all_memory)
        )
        
    catch e
        @error "  Benchmark failed: $e"
        return create_failed_result(config, "benchmark_failed: $e")
    end
end

function create_failed_result(config, reason, failed_runs=0)
    return Dict(
        "config" => config,
        "status" => "failed",
        "reason" => reason
    )
end

