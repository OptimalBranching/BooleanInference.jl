"""
    benchmark_dataset(problem_type, dataset_path; solver=nothing, verify=true)

Run benchmark on a single dataset file/directory.

# Arguments
- `problem_type::Type{<:AbstractBenchmarkProblem}`: The type of problem to benchmark
- `dataset_path::AbstractString`: Path to the dataset file or directory
- `solver`: The solver to use (defaults to the problem type's default solver)
- `verify::Bool`: Whether to verify solution correctness (default: true). Set to false to skip
  verification and only measure performance. When false, all runs are considered successful.
"""
function benchmark_dataset(problem_type::Type{<:AbstractBenchmarkProblem},
                           dataset_path::AbstractString;
                           solver::Union{AbstractSolver, Nothing}=nothing,
                           verify::Bool=true)
    actual_solver = isnothing(solver) ? default_solver(problem_type) : solver
    warmup = actual_solver.warmup
    solver_info = solver_name(actual_solver)
    
    @info "Benchmarking: $dataset_path"
    @info "Using solver: $solver_info"
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
    all_results = Any[]
    
    # Warmup if requested
    if warmup
        @info "  Performing warmup..."
        solve_instance(problem_type, instances[1], actual_solver)
        @info "  Warmup completed, starting verification and timing..."
    else
        @info "  Skipping warmup, starting verification and timing..."
    end
    
    for (i, instance) in enumerate(instances)
        # Measure time directly while solving
        result = nothing
        elapsed_time = @elapsed begin
            result = solve_instance(problem_type, instance, actual_solver)
        end
        push!(all_times, elapsed_time)
        push!(all_results, result)

        # For CircuitSAT, print SAT/UNSAT result
        if problem_type == CircuitSATProblem && result !== nothing
            satisfiable, _ = result
            instance_name = hasfield(typeof(instance), :name) ? instance.name : "Instance $i"
            println("  $instance_name: ", satisfiable ? "SAT" : "UNSAT", " ($(round(elapsed_time, digits=4))s)")
        end
        
        # Verify solution if requested
        if verify
            is_correct = verify_solution(problem_type, instance, result)
            !is_correct && @error "  Instance $i: Incorrect solution"
        end           
        
        if i % 10 == 0 || i == length(instances)
            @info "  Completed $i/$(length(instances)) instances"
        end
    end        
    return Dict(
        "dataset_path" => dataset_path,
        "instances_tested" => length(instances),
        "solver" => solver_info,
        "all_time" => all_times,
        "all_results" => all_results
    )
end
