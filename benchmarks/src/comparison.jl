function run_full_benchmark(problem_type::Type{<:AbstractBenchmarkProblem}; 
                           solver=nothing,
                           dataset_per_config::Int=50,
                           force_regenerate_datasets::Bool=false)
    
    problem_name = lowercase(string(problem_type)[1:end-7])
    configs = default_configs(problem_type)
    
    @info "Preparing $problem_name datasets..."
    generate_datasets(problem_type; 
                     configs=configs, 
                     per_config=dataset_per_config, 
                     include_solution=true,
                     force_regenerate=force_regenerate_datasets)
    
    @info "Running $problem_name benchmarks..."
    results = benchmark_problem(problem_type; 
                               configs=configs,
                               solver=solver)
    
    print_benchmark_summary(results)
    
    return results
end

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

function run_solver_comparison(problem_type::Type{<:AbstractBenchmarkProblem}, 
                               config_tuples::Vector{<:Tuple}; 
                               dataset_per_config::Int=50,
                               force_regenerate_datasets::Bool=false)
    solvers = available_solvers(problem_type)
    results = Dict()
    
    for solver in solvers
        solver_name_str = solver_name(solver)
        @info "Running benchmark with solver: $solver_name_str"
        configs = default_configs(problem_type)
        if !isempty(config_tuples)
            configs = [config(problem_type, t) for t in config_tuples]
        end
        
        problem_name = lowercase(string(problem_type)[1:end-7])
        
        generate_datasets(problem_type; 
                         configs=configs, 
                         per_config=dataset_per_config, 
                         include_solution=true,
                         force_regenerate=force_regenerate_datasets)
        
        solver_results = benchmark_problem(problem_type; configs=configs, solver=solver)
        results[solver_name_str] = solver_results
    end
    
    return results
end

function print_solver_comparison_summary(solver_results::Dict)
    if isempty(solver_results)
        println("No solver results to compare!")
        return
    end
    
    println("\n" * repeat("=", 80))
    println("SOLVER COMPARISON SUMMARY")
    println(repeat("=", 80))
    
    first_results = first(values(solver_results))
    configs = [result["config"] for result in first_results if result["status"] == "success"]
    
    if isempty(configs)
        println("No successful results to compare!")
        return
    end
    
    solver_names = collect(keys(solver_results))
    header = "| Config   "
    for solver in solver_names
        header *= "| $(rpad(solver, 10)) "
    end
    header *= "|"
    
    println(repeat("+", length(header)))
    println(header)
    println(repeat("-", length(header)))
    
    for config in configs
        config_str = "$(config.m)x$(config.n)"
        row = "| $(rpad(config_str, 8)) "
        
        for solver in solver_names
            solver_result = solver_results[solver]
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
            row *= "| $(rpad(time_str, 10)) "
        end
        row *= "|"
        println(row)
    end
    println(repeat("+", length(header)))
    println(repeat("=", 80))
end

function compare_solver_results(name1::String, results1, name2::String, results2)
    println(repeat("+", 80))
    println("| $(rpad("Config", 8)) | $(rpad("$name1", 15)) | $(rpad("$name2", 15)) | $(rpad("Winner", 20)) |")
    println(repeat("-", 80))
    
    success1 = filter(r -> r["status"] == "success", results1)
    success2 = filter(r -> r["status"] == "success", results2)
    
    for r1 in success1
        config = r1["config"]
        config_str = "$(config.m)x$(config.n)"
        
        r2 = findfirst(r -> r["config"] == config, success2)
        if !isnothing(r2)
            r2 = success2[r2]
            
            time1 = r1["median_time"] 
            time2 = r2["median_time"]
            time1_str = format_time(time1)
            time2_str = format_time(time2)
            
            if time1 < time2
                winner_str = "$name1 ($(round(time2/time1, digits=2))x)"
            elseif time2 < time1
                winner_str = "$name2 ($(round(time1/time2, digits=2))x)"
            else
                winner_str = "Tie"
            end
            
            println("| $(rpad(config_str, 8)) | $(rpad(time1_str, 15)) | $(rpad(time2_str, 15)) | $(rpad(winner_str, 20)) |")
        else
            println("| $(rpad(config_str, 8)) | $(rpad(format_time(r1["median_time"]), 15)) | $(rpad("FAILED", 15)) | $(rpad(name1, 20)) |")
        end
    end
    println(repeat("+", 80))
end

