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
all_mostocc_branches = Float64[]
all_mingamma_branches = Float64[]
all_n_labels = String[]

for (n_idx, n_value) in enumerate(n_values)
    results_nxn = load_dataset_results(result_dir, "numbers_$(n_value)x$(n_value)")
    
    # Collect MostOccurrenceSelector branches (best k for each instance)
    bi_results = filter_results(results_nxn, solver_name="BI")
    mostocc_k_to_branches = Dict{Int, Vector{Int}}()
    mingamma_k_to_branches = Dict{Int, Vector{Int}}()
    
    for result in bi_results
        selector_type = result.solver_config["selector_type"]
        measure = result.solver_config["measure"]
        k = result.solver_config["selector_max_tensors"]
        
        if selector_type == "MostOccurrenceSelector" && measure == "NumHardTensors" && k in k_values
            mostocc_k_to_branches[k] = result.branches
        elseif selector_type == "MinGammaSelector" && measure == "NumHardTensors" && k in k_values
            mingamma_k_to_branches[k] = result.branches
        end
    end
    
    # Skip if no data
    (isempty(mostocc_k_to_branches) || isempty(mingamma_k_to_branches)) && continue
    
    # Get number of instances
    num_instances = length(first(values(mostocc_k_to_branches)))
    
    # For each selector, use best k (minimum branches) for each instance
    mostocc_best_branches = Int[]
    mingamma_best_branches = Int[]
    
    for i in 1:num_instances
        # MostOccurrenceSelector best k
        mostocc_instance_branches = [mostocc_k_to_branches[k][i] for k in k_values]
        best_idx = argmin(mostocc_instance_branches)
        push!(mostocc_best_branches, mostocc_instance_branches[best_idx])
        
        # MinGammaSelector best k
        mingamma_instance_branches = [mingamma_k_to_branches[k][i] for k in k_values]
        best_idx = argmin(mingamma_instance_branches)
        push!(mingamma_best_branches, mingamma_instance_branches[best_idx])
    end
    
    # Append to global arrays
    append!(all_mostocc_branches, mostocc_best_branches)
    append!(all_mingamma_branches, mingamma_best_branches)
    append!(all_n_labels, fill("n=$(n_value*2)", num_instances))
end

# Create figure with scatter plot
fig = Figure(size = (400, 300))

ax = Axis(fig[1, 1], 
          xlabel = "MostOccurrenceSelector Branches (best k)", 
          ylabel = "MinGammaSelector Branches (best k)",
          xscale = log10,
          yscale = log10,
          title = "MostOccurrenceSelector vs MinGammaSelector")

# Plot with different colors for each n value
for (n_idx, n_value) in enumerate(n_values)
    mask = all_n_labels .== "n=$(n_value*2)"
    if any(mask)
        mostocc_vals = all_mostocc_branches[mask]
        mingamma_vals = all_mingamma_branches[mask]
        scatter!(ax, mostocc_vals, mingamma_vals; 
                 color = (colors[n_idx], 0.6),
                 markersize = 8,
                 label = "n=$(n_value*2)")
    end
end

# Diagonal line (y = x)
max_val = max(maximum(all_mostocc_branches), maximum(all_mingamma_branches))
lines!(ax, [1, max_val], [1, max_val]; 
       color = :black, 
       linestyle = :dash,
       linewidth = 1)

axislegend(ax, position = :lt, framevisible = false)

save("branch_selector_comparison_scatter.png", fig)
fig

