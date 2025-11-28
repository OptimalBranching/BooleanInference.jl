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

# Collect all data across different n values
all_hardtensor_branches = Float64[]
all_unfixvars_branches = Float64[]
all_n_labels = String[]

for (n_idx, n_value) in enumerate(n_values)
    results_nxn = load_dataset_results(result_dir, "numbers_$(n_value)x$(n_value)")
    
    # Collect MostOccurrenceSelector branches with different measures
    bi_results = filter_results(results_nxn, solver_name="BI")
    hardtensor_k_to_branches = Dict{Int, Vector{Int}}()
    unfixvars_k_to_branches = Dict{Int, Vector{Int}}()
    
    for result in bi_results
        selector_type = result.solver_config["selector_type"]
        measure = result.solver_config["measure"]
        k = result.solver_config["selector_max_tensors"]
        
        if selector_type == "MostOccurrenceSelector" && k in k_values
            if measure == "NumHardTensors"
                hardtensor_k_to_branches[k] = result.branches
            elseif measure == "NumUnfixedVars"
                unfixvars_k_to_branches[k] = result.branches
            end
        end
    end
    
    # Skip if no data
    (isempty(hardtensor_k_to_branches) || isempty(unfixvars_k_to_branches)) && continue
    
    # Get number of instances
    num_instances = length(first(values(hardtensor_k_to_branches)))
    
    # For each measure, use best k (minimum branches) for each instance
    hardtensor_best_branches = Int[]
    unfixvars_best_branches = Int[]
    
    for i in 1:num_instances
        # NumHardTensors best k
        hardtensor_instance_branches = [hardtensor_k_to_branches[k][i] for k in k_values]
        best_idx = argmin(hardtensor_instance_branches)
        push!(hardtensor_best_branches, hardtensor_instance_branches[best_idx])
        
        # NumUnfixedVars best k
        unfixvars_instance_branches = [unfixvars_k_to_branches[k][i] for k in k_values]
        best_idx = argmin(unfixvars_instance_branches)
        push!(unfixvars_best_branches, unfixvars_instance_branches[best_idx])
    end
    
    # Append to global arrays
    append!(all_hardtensor_branches, hardtensor_best_branches)
    append!(all_unfixvars_branches, unfixvars_best_branches)
    append!(all_n_labels, fill("n=$(n_value*2)", num_instances))
end

# Create figure with scatter plot
fig = Figure(size = (600, 450))

ax = Axis(fig[1, 1], 
          xlabel = "NumHardTensors Branches (best k)", 
          ylabel = "NumUnfixedVars Branches (best k)",
          xscale = log10,
          yscale = log10,
          title = "MostOccurrenceSelector: NumHardTensors vs NumUnfixedVars")

# Plot with different colors for each n value
for (n_idx, n_value) in enumerate(n_values)
    mask = all_n_labels .== "n=$(n_value*2)"
    if any(mask)
        hardtensor_vals = all_hardtensor_branches[mask]
        unfixvars_vals = all_unfixvars_branches[mask]
        scatter!(ax, hardtensor_vals, unfixvars_vals; 
                 color = (colors[n_idx], 0.6),
                 markersize = 8,
                 label = "n=$(n_value*2)")
    end
end

# Diagonal line (y = x)
max_val = max(maximum(all_hardtensor_branches), maximum(all_unfixvars_branches))
lines!(ax, [10, max_val], [10, max_val]; 
       color = :black, 
       linestyle = :dash,
       linewidth = 1)

axislegend(ax, position = :lt, framevisible = false)

save("branch_measure_comparison_mostocc_scatter.png", fig)
fig

