# run_full_benchmark is deprecated - implement per problem type

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
    run_solver_comparison(problem_type, dataset_paths; solvers=nothing)

Compare multiple solvers on the same datasets.
"""
function run_solver_comparison(problem_type::Type{<:AbstractBenchmarkProblem}, 
                               dataset_paths::Vector{String};
                               solvers::Union{Vector{<:AbstractSolver}, Nothing}=nothing)
    solver_list = isnothing(solvers) ? available_solvers(problem_type) : solvers
    results = Dict()
    
    for solver in solver_list
        solver_name_str = solver_name(solver)
        @info "Running benchmark with solver: $solver_name_str"
        
        solver_results = []
        for path in dataset_paths
            result = benchmark_dataset(problem_type, path; solver=solver, verify=solver.verify)
            if !isnothing(result)
                push!(solver_results, result)
            end
        end
        
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
    
    # Get all successful results (non-nothing)
    first_results = first(values(solver_results))
    successful_results = filter(!isnothing, first_results)
    
    if isempty(successful_results)
        println("No successful results to compare!")
        return
    end
    
    # Get unique dataset paths
    dataset_paths = unique([result["dataset_path"] for result in successful_results])
    
    solver_names = collect(keys(solver_results))
    header = "| Dataset           "
    for solver in solver_names
        header *= "| $(rpad(solver, 12)) "
    end
    header *= "|"
    
    println(header)
    println(repeat("-", length(header)))
    
    for path in dataset_paths
        # Extract a short name from path
        path_parts = splitpath(path)
        dataset_name = length(path_parts) > 0 ? path_parts[end] : path
        dataset_str = dataset_name[1:min(length(dataset_name), 17)]
        row = "| $(rpad(dataset_str, 17)) "
        
        for solver in solver_names
            solver_result = solver_results[solver]
            matching_result = findfirst(r -> !isnothing(r) && r["dataset_path"] == path, solver_result)
            
            if isnothing(matching_result)
                time_str = "FAILED"
            else
                result = solver_result[matching_result]
                median_time = result["median_time"]
                time_str = format_time(median_time)
            end
            row *= "| $(rpad(time_str, 12)) "
        end
        row *= "|"
        println(row)
    end
    println(repeat("=", 80))
end

function compare_solver_results(name1::String, results1, name2::String, results2)
    println(repeat("+", 80))
    println("| $(rpad("Dataset", 15)) | $(rpad("$name1", 15)) | $(rpad("$name2", 15)) | $(rpad("Winner", 20)) |")
    println(repeat("-", 80))
    
    success1 = filter(!isnothing, results1)
    success2 = filter(!isnothing, results2)
    
    for r1 in success1
        path = r1["dataset_path"]
        path_parts = splitpath(path)
        dataset_name = length(path_parts) > 0 ? path_parts[end] : path
        dataset_str = dataset_name[1:min(length(dataset_name), 15)]
        
        r2 = findfirst(r -> r["dataset_path"] == path, success2)
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
            
            println("| $(rpad(dataset_str, 15)) | $(rpad(time1_str, 15)) | $(rpad(time2_str, 15)) | $(rpad(winner_str, 20)) |")
        else
            println("| $(rpad(dataset_str, 15)) | $(rpad(format_time(r1["median_time"]), 15)) | $(rpad("FAILED", 15)) | $(rpad(name1, 20)) |")
        end
    end
    println(repeat("+", 80))
end
