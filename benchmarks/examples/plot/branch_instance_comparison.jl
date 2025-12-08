using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
using CairoMakie
using BooleanInferenceBenchmarks
using Statistics

result_dir = resolve_results_dir("factoring")

n_values = [10, 12, 14, 16, 18, 20]
k_values = [1, 2, 3, 4, 5]

# Colors for different n values
colors = [:red, :orange, :green, :blue, :purple, :brown]
markers = [:circle, :utriangle, :diamond, :pentagon, :hexagon, :cross]

# Collect all data across different n values
all_bi_branches = Float64[]
all_kissat_branches = Float64[]
all_minisat_branches = Float64[]
all_n_labels = String[]

for (n_idx, n_value) in enumerate(n_values)
    results_nxn = load_dataset_results(result_dir, "numbers_$(n_value)x$(n_value)")
    
    # Collect BI branches (best k for each instance)
    bi_results = filter_results(results_nxn, solver_name="BI")
    k_to_branches = Dict{Int, Vector{Int}}()
    
    for result in bi_results
        selector_type = result.solver_config["selector_type"]
        measure = result.solver_config["measure"]
        
        if selector_type == "MostOccurrenceSelector" && measure == "NumHardTensors"
            k = result.solver_config["selector_max_tensors"]
            if k in k_values
                k_to_branches[k] = result.branches
            end
        end
    end
    
    # Skip if no BI data
    isempty(k_to_branches) && continue
    
    # Get Kissat and MiniSAT branches
    kissat_results = filter_results(results_nxn, solver_name="Kissat")
    minisat_results = filter_results(results_nxn, solver_name="MiniSAT")
    
    kissat_branches = isempty(kissat_results) ? Int[] : kissat_results[1].branches
    minisat_branches = isempty(minisat_results) ? Int[] : minisat_results[1].branches
    
    # Get number of instances
    num_instances = length(first(values(k_to_branches)))
    
    # For BI, use best k (minimum branches) for each instance
    bi_best_branches = Int[]
    for i in 1:num_instances
        instance_branches = [k_to_branches[k][i] for k in k_values]
        best_idx = argmin(instance_branches)
        push!(bi_best_branches, instance_branches[best_idx])
    end
    
    # Append to global arrays
    append!(all_bi_branches, bi_best_branches)
    append!(all_kissat_branches, kissat_branches)
    append!(all_minisat_branches, minisat_branches)
    append!(all_n_labels, fill("n=$(n_value*2)", num_instances))
end

# Create figure with single scatter plot
fig = Figure(size = (600, 450))

ax = Axis(fig[1, 1], 
          xlabel = "BI Branches (best k)", 
          ylabel = "External Solver Branches",
          xscale = log10,
          yscale = log10,
          title = "BI vs External Solvers")

# Plot Kissat with different markers for each n value
kissat_plotted = false
for (n_idx, n_value) in enumerate(n_values)
    mask = all_n_labels .== "n=$(n_value*2)"
    if any(mask)
        bi_vals = all_bi_branches[mask]
        kissat_vals = all_kissat_branches[mask]
        scatter!(ax, bi_vals, kissat_vals; 
                 color = (:blue, 0.5),
                 marker = markers[n_idx],
                 markersize = 8,
                 label = kissat_plotted ? nothing : "Kissat")
        if !kissat_plotted
            kissat_plotted = true
        end
    end
end

# Plot MiniSAT with different markers for each n value
minisat_plotted = false
for (n_idx, n_value) in enumerate(n_values)
    mask = all_n_labels .== "n=$(n_value*2)"
    if any(mask)
        bi_vals = all_bi_branches[mask]
        minisat_vals = all_minisat_branches[mask]
        scatter!(ax, bi_vals, minisat_vals; 
                 color = (:green, 0.5),
                 marker = markers[n_idx],
                 markersize = 8,
                 label = minisat_plotted ? nothing : "MiniSAT")
        if !minisat_plotted
            minisat_plotted = true
        end
    end
end

# Diagonal line (y = x)
max_val = max(maximum(all_bi_branches), maximum(all_kissat_branches), maximum(all_minisat_branches))
lines!(ax, [1, max_val], [1, max_val]; 
       color = :black, 
       linestyle = :dash,
       linewidth = 1)

axislegend(ax, position = :lt, framevisible = false)

save("branch_instance_comparison.png", fig)
fig

