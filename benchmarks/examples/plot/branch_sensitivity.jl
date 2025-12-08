using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
using CairoMakie
using BooleanInferenceBenchmarks
using Statistics

result_dir = resolve_results_dir("factoring")

n_value = 18
k_values = [1, 2, 3, 4, 5]

# Load results for n=20
results_nxn = load_dataset_results(result_dir, "numbers_$(n_value)x$(n_value)")
bi_results = filter_results(results_nxn, solver_name="BI")

# Collect branches for each (k, instance_idx)
# Structure: k_to_branches[k] = [branch_for_instance_1, branch_for_instance_2, ...]
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

# Get number of instances (assuming all k have same number)
num_instances = length(first(values(k_to_branches)))

# Build matrix: rows = instances, cols = k values
branch_matrix = zeros(Int, num_instances, length(k_values))
for (col, k) in enumerate(k_values)
    branch_matrix[:, col] = k_to_branches[k]
end

# Sort instances by sensitivity for better visualization
sensitivities = [std(branch_matrix[i, :]) / mean(branch_matrix[i, :]) for i in 1:num_instances]
sorted_idx = sortperm(sensitivities, rev=true)  # Most sensitive first
branch_matrix_sorted = branch_matrix[sorted_idx, :]

# Create figure with heatmap
fig = Figure(size = (900, 700))

# Heatmap: log scale for better visualization
log_branches = log10.(branch_matrix_sorted)

ax = Axis(fig[1, 1], 
          xlabel = "max_tensors (k)", 
          ylabel = "Instance (sorted by sensitivity)",
          title = "Branch Count vs Region Size for Each Instance",
          xticks = (1:length(k_values), string.(k_values)),
          yticks = (1:5:num_instances, string.(1:5:num_instances)))

hm = heatmap!(ax, log_branches', 
              colormap = :viridis)

Colorbar(fig[1, 2], hm, label = "log₁₀(Branches)")

# Add a second subplot showing the trend lines for top 5 most/least sensitive
ax2 = Axis(fig[2, 1:2], 
           xlabel = "max_tensors (k)", 
           ylabel = "Branches",
           title = "Highlighted: Top 5 Most/Least Sensitive Instances",
           xticks = k_values,
           yscale = log10)

# Plot all instances in light gray background
for i in 1:num_instances
    lines!(ax2, k_values, branch_matrix[i, :]; 
           color = (:gray, 0.2),
           linewidth = 0.5)
end

# Highlight top 5 most sensitive (red shades)
red_colors = [RGBf(0.8, 0.1*i, 0.1*i) for i in 0:4]
for (rank, i) in enumerate(sorted_idx[1:5])
    lines!(ax2, k_values, branch_matrix[i, :]; 
           color = red_colors[rank],
           linewidth = 2)
end

# Highlight top 5 least sensitive (blue shades)
blue_colors = [RGBf(0.1*i, 0.1*i, 0.8) for i in 0:4]
for (rank, i) in enumerate(sorted_idx[end-4:end])
    lines!(ax2, k_values, branch_matrix[i, :]; 
           color = blue_colors[rank],
           linewidth = 2,
           linestyle = :dash)
end

# Mean line
mean_branches = [mean(branch_matrix[:, col]) for col in 1:length(k_values)]
lines!(ax2, k_values, mean_branches; 
       color = :black, 
       linewidth = 3)

save("branch_instance_k_sensitivity.png", fig)
fig
