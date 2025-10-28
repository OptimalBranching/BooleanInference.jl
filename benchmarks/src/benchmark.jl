"""
    benchmark_dataset(problem_type, dataset_path; solver=nothing)

Run benchmark on a single dataset file/directory.
"""
function benchmark_dataset(problem_type::Type{<:AbstractBenchmarkProblem}, dataset_path::String; solver=nothing)
    actual_solver = isnothing(solver) ? default_solver(problem_type) : solver
    solver_info = solver_name(actual_solver)
    
    @info "Benchmarking: $dataset_path"
    @info "Using solver: $solver_info"
    
    try
        if !isfile(dataset_path) && !isdir(dataset_path)
            @error "Dataset not found: $dataset_path"
            return nothing
        end
        
        @info "  Loading instances from: $dataset_path"
        instances = read_instances(problem_type, dataset_path)
        @info "  Testing $(length(instances)) instances"
        
        if isempty(instances)
            @error "  No instances found in dataset"
            return nothing
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
            @warn "All instances failed"
            return nothing
        end
        
        return Dict(
            "dataset_path" => dataset_path,
            "instances_tested" => length(instances),
            "correct_runs" => correct_runs,
            "successful_runs" => successful_runs,
            "accuracy_rate" => correct_runs / length(instances),
            "median_time" => median(all_times),
            "median_memory" => median(all_memory),
            "solver" => solver_info
        )
        
    catch e
        @error "  Benchmark failed: $e"
        return nothing
    end
end

