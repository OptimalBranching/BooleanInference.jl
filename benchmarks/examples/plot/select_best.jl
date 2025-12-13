using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
using CairoMakie
using BooleanInferenceBenchmarks
using Statistics

result_dir = resolve_results_dir("factoring")

n = [20]
branches_n = []
times_n = []
best_max_tensors_n = []

kissat_branches_n = []
kissat_times_n = []
minisat_branches_n = []
minisat_times_n = []
gurobi_times_n = []
xsat_times_n = []

for nn in n
    results_nxn = load_dataset_results(result_dir, "numbers_$(nn)x$(nn)")
    bi_results = filter_results(results_nxn, solver_name="BI")

    # Filter results with same selector_type, measure, set_cover_solver but different selector_max_tensors
    candidate_results = []
    for result in bi_results
        if result.solver_config["selector_type"] == "MostOccurrenceSelector" && 
           result.solver_config["measure"] == "NumUnfixedVars" && 
           result.solver_config["set_cover_solver"] == "GreedyMerge" &&
           haskey(result.solver_config, "selector_max_tensors")
            push!(candidate_results, result)
        end
    end
    
    if isempty(candidate_results)
        @warn "No candidate results found for n=$nn"
        push!(branches_n, Int[])
        push!(times_n, Float64[])
        push!(best_max_tensors_n, [])
    else
        # For each instance, find the best (minimum branches) across different selector_max_tensors
        num_instances = length(candidate_results[1].branches)
        best_branches = Int[]
        best_times = Float64[]
        best_max_tensors_list = []
        
        for instance_idx in 1:num_instances
            best_branch_value = Inf
            best_time_value = Inf
            best_max_tensors = nothing
            
            # for result in candidate_results
            #     if instance_idx <= length(result.branches)
            #         branch_value = result.branches[instance_idx]
            #         if branch_value < best_branch_value
            #             best_branch_value = branch_value
            #             best_time_value = result.times[instance_idx]
            #             best_max_tensors = result.solver_config["selector_max_tensors"]
            #         end
            #     end
            # end
            for result in candidate_results
                if instance_idx <= length(result.branches)
                    time_value = result.times[instance_idx]
                    if time_value < best_time_value
                        best_time_value = time_value
                        best_branch_value = result.branches[instance_idx]
                        best_max_tensors = result.solver_config["selector_max_tensors"]
                    end
                end
            end
            
            push!(best_branches, best_branch_value)
            push!(best_times, best_time_value)
            push!(best_max_tensors_list, best_max_tensors)
        end
        
        push!(branches_n, best_branches)
        push!(times_n, best_times)
        push!(best_max_tensors_n, best_max_tensors_list)
    end

    kissat_results = filter_results(results_nxn, solver_name="Kissat")
    minisat_results = filter_results(results_nxn, solver_name="MiniSAT")
    gurobi_results = filter_results(results_nxn, solver_name="IP-Gurobi")
    xsat_results = filter_results(results_nxn, solver_name="X-SAT")
    
    push!(kissat_branches_n, !isempty(kissat_results) ? kissat_results[1].branches : Int[])
    push!(kissat_times_n, !isempty(kissat_results) ? kissat_results[1].times : Float64[])
    push!(minisat_branches_n, !isempty(minisat_results) ? minisat_results[1].branches : Int[])
    push!(minisat_times_n, !isempty(minisat_results) ? minisat_results[1].times : Float64[])
    push!(gurobi_times_n, !isempty(gurobi_results) ? gurobi_results[1].times : Float64[])
    push!(xsat_times_n, !isempty(xsat_results) ? xsat_results[1].times : Float64[])
end

# Print results
println("=" ^ 80)
println("Results for n=20")
println("=" ^ 80)

if !isempty(branches_n) && !isempty(branches_n[1])
    best_branches = branches_n[1]
    best_times = times_n[1]
    best_max_tensors = best_max_tensors_n[1]
    
    println("\nNumber of instances: $(length(best_branches))")
    println("\nBest branches per instance (selected from different selector_max_tensors):")
    for (i, (br, tm, mt)) in enumerate(zip(best_branches, best_times, best_max_tensors))
        println("  Instance $i: branches = $br, time = $(round(tm, digits=3))s, selector_max_tensors = $mt")
    end
    
    println("\nStatistics:")
    println("  Mean branches: $(round(mean(best_branches), digits=2))")
    println("  Min branches: $(minimum(best_branches))")
    println("  Max branches: $(maximum(best_branches))")
    println("  Median branches: $(round(median(best_branches), digits=2))")
    println("  Mean time: $(round(mean(best_times), digits=3))s")
    println("  Total time: $(round(sum(best_times), digits=3))s")
else
    println("\nNo results found!")
end