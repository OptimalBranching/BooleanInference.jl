using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
using CairoMakie
using BooleanInferenceBenchmarks
using Statistics

result_dir = resolve_results_dir("factoring")

n_values = [10, 12, 14]
k_values = [1, 2, 3, 4, 5]

# Data structure: data[n_idx][k] = vector of branches
hardtensor_data = Dict{Int, Dict{Int, Vector{Int}}}()
unfixvars_data = Dict{Int, Dict{Int, Vector{Int}}}()

# Reference solver data: ref_branches[n_idx] = (kissat_mean, minisat_mean)
ref_branches = Dict{Int, Tuple{Float64, Float64}}()

for (n_idx, nn) in enumerate(n_values)
    results_nxn = load_dataset_results(result_dir, "numbers_$(nn)x$(nn)")
    bi_results = filter_results(results_nxn, solver_name="BI")
    
    hardtensor_data[n_idx] = Dict{Int, Vector{Int}}()
    unfixvars_data[n_idx] = Dict{Int, Vector{Int}}()
    
    # Collect selector results grouped by max_tensors (k)
    for result in bi_results
        selector_type = result.solver_config["selector_type"]
        k = result.solver_config["selector_max_tensors"]
        measure = result.solver_config["measure"]

        if selector_type == "MinGammaSelector" && k in k_values
            if measure == "NumHardTensors"
                hardtensor_data[n_idx][k] = result.branches
            elseif measure == "NumUnfixedVars"
                unfixvars_data[n_idx][k] = result.branches
            end
        end
    end
    
    # Get reference solver branches
    kissat_results = filter_results(results_nxn, solver_name="Kissat")
    minisat_results = filter_results(results_nxn, solver_name="MiniSAT")
    
    kissat_mean = !isempty(kissat_results) ? mean(kissat_results[1].branches) : NaN
    minisat_mean = !isempty(minisat_results) ? mean(minisat_results[1].branches) : NaN
    
    ref_branches[n_idx] = (kissat_mean, minisat_mean)
end

# Create figure with 2x3 subplots
fig = Figure(size = (1200, 450))

# Offset for side-by-side boxplots
offset_hardtensor = -0.2
offset_unfixvars = 0.2

for (n_idx, nn) in enumerate(n_values)
    # 2x3 layout: row = (n_idx-1)÷3 + 1, col = (n_idx-1)%3 + 1
    row = (n_idx - 1) ÷ 3 + 1
    col = (n_idx - 1) % 3 + 1
    
    ax = Axis(fig[row, col], 
              xlabel = "max_tensors (k)", 
              ylabel = "Branches", 
              yscale = log10,
              title = "Bit length = $(nn*2)",
              xticks = (k_values, string.(k_values)))
    
    # Flatten data for HardTensor boxplot
    hardtensor_x = Float64[]
    hardtensor_y = Float64[]
    for k in k_values
        if haskey(hardtensor_data[n_idx], k)
            for branch in hardtensor_data[n_idx][k]
                push!(hardtensor_x, k + offset_hardtensor)
                push!(hardtensor_y, Float64(branch))
            end
        end
    end
    
    # Flatten data for UnfixVars boxplot
    unfixvars_x = Float64[]
    unfixvars_y = Float64[]
    for k in k_values
        if haskey(unfixvars_data[n_idx], k)
            for branch in unfixvars_data[n_idx][k]
                push!(unfixvars_x, k + offset_unfixvars)
                push!(unfixvars_y, Float64(branch))
            end
        end
    end
    
    # Draw boxplots
    if !isempty(hardtensor_y)
        boxplot!(ax, hardtensor_x, hardtensor_y; label = "HardTensor", width = 0.35, color = :steelblue)
    end
    if !isempty(unfixvars_y)
        boxplot!(ax, unfixvars_x, unfixvars_y; label = "UnfixVars", width = 0.35, color = :orange)
    end
    
    # Draw horizontal lines for reference solvers
    kissat_mean, minisat_mean = ref_branches[n_idx]
    
    if !isnan(kissat_mean)
        hlines!(ax, [kissat_mean]; color = :red, linestyle = :dash, linewidth = 2, label = "Kissat")
    end
    if !isnan(minisat_mean)
        hlines!(ax, [minisat_mean]; color = :green, linestyle = :dot, linewidth = 2, label = "MiniSAT")
    end
end

# Add shared legend at bottom
Legend(fig[2, 1:3], fig.content[1], orientation = :horizontal, framevisible = false, nbanks = 1)

save("branch_measure_comparison_mingamma.png", fig)
fig
