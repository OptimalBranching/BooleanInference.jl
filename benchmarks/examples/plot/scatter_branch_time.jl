using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
using CairoMakie
using BooleanInferenceBenchmarks
using Statistics

result_dir = resolve_results_dir("factoring")

n_values = [10, 12, 14, 16, 18, 20]
k_values = [1, 2, 3, 4, 5]

# Collect data for all solvers
bi_all_data = Tuple{Float64, Float64}[]
kissat_all_data = Tuple{Float64, Float64}[]
minisat_all_data = Tuple{Float64, Float64}[]

for (n_idx, nn) in enumerate(n_values)
    results_nxn = load_dataset_results(result_dir, "numbers_$(nn)x$(nn)")
    
    # BooleanInference data
    bi_results = filter_results(results_nxn, solver_name="BI")
    for result in bi_results
        selector_type = result.solver_config["selector_type"]
        measure = result.solver_config["measure"]
        
        if selector_type == "MostOccurrenceSelector" && measure == "NumHardTensors"
            k = result.solver_config["selector_max_tensors"]
            if k in k_values
                for (time, branch) in zip(result.times, result.branches)
                    push!(bi_all_data, (time, Float64(branch)))
                end
            end
        end
    end
    
    # Kissat data
    kissat_results = filter_results(results_nxn, solver_name="Kissat")
    if !isempty(kissat_results)
        result = kissat_results[1]
        for (time, branch) in zip(result.times, result.branches)
            push!(kissat_all_data, (time, Float64(branch)))
        end
    end
    
    # MiniSAT data
    minisat_results = filter_results(results_nxn, solver_name="MiniSAT")
    if !isempty(minisat_results)
        result = minisat_results[1]
        for (time, branch) in zip(result.times, result.branches)
            push!(minisat_all_data, (time, Float64(branch)))
        end
    end
end

# Create single scatter plot with all three solvers
fig = Figure(size = (600, 600))

ax = Axis(fig[1, 1], 
          xlabel = "Time (s)", 
          ylabel = "Branches",
          xscale = log10,
          yscale = log10,
          title = "Time vs Branches")

# Plot each solver with different color and marker
if !isempty(bi_all_data)
    bi_times = [d[1] for d in bi_all_data]
    bi_branches = [d[2] for d in bi_all_data]
    scatter!(ax, bi_times, bi_branches; 
             label = "BooleanInference", 
             color = (:red, 0.5),
             marker = :circle,
             markersize = 8)
end

if !isempty(kissat_all_data)
    kissat_times = [d[1] for d in kissat_all_data]
    kissat_branches = [d[2] for d in kissat_all_data]
    scatter!(ax, kissat_times, kissat_branches; 
             label = "Kissat", 
             color = (:blue, 0.5),
             marker = :utriangle,
             markersize = 8)
end

if !isempty(minisat_all_data)
    minisat_times = [d[1] for d in minisat_all_data]
    minisat_branches = [d[2] for d in minisat_all_data]
    scatter!(ax, minisat_times, minisat_branches; 
             label = "MiniSAT", 
             color = (:green, 0.5),
             marker = :diamond,
             markersize = 8)
end

axislegend(ax, position = :rb, framevisible = false)

save("scatter_branch_time.png", fig)
fig

