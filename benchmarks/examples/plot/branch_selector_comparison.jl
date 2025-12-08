using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
using CairoMakie
using BooleanInferenceBenchmarks
using Statistics

result_dir = resolve_results_dir("factoring")

n_values = [10, 12, 14]
k_values = [1, 2, 3, 4, 5]

# Data structure: branches_data[selector][n_idx][k] = vector of branches
mingamma_data = Dict{Int, Dict{Int, Vector{Int}}}()
mostocc_data = Dict{Int, Dict{Int, Vector{Int}}}()

# Reference solver data: ref_branches[n_idx] = (kissat_mean, minisat_mean)
ref_branches = Dict{Int, Tuple{Float64, Float64}}()

for (n_idx, nn) in enumerate(n_values)
    results_nxn = load_dataset_results(result_dir, "numbers_$(nn)x$(nn)")
    bi_results = filter_results(results_nxn, solver_name="BI")
    
    mingamma_data[n_idx] = Dict{Int, Vector{Int}}()
    mostocc_data[n_idx] = Dict{Int, Vector{Int}}()
    
    # Collect selector results grouped by max_tensors (k)
    for result in bi_results
        selector_type = result.solver_config["selector_type"]
        k = result.solver_config["selector_max_tensors"]
        measure = result.solver_config["measure"]

        if measure == "NumHardTensors"
            if k in k_values
                if selector_type == "MinGammaSelector"
                    @assert !haskey(mingamma_data[n_idx], k) "Please check the choice of parameters, and do not override the existing data."
                    mingamma_data[n_idx][k] = result.branches
                elseif selector_type == "MostOccurrenceSelector"
                    @assert !haskey(mostocc_data[n_idx], k) "Please check the choice of parameters, and do not override the existing data."
                    mostocc_data[n_idx][k] = result.branches
                end
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

# Create figure with 3 subplots (one per dataset)
fig = Figure(size = (1200, 450))

# Offset for side-by-side boxplots
offset_mingamma = -0.2
offset_mostocc = 0.2

for (n_idx, nn) in enumerate(n_values)
    ax = Axis(fig[1, n_idx], 
              xlabel = "max_tensors (k)", 
              ylabel = "Branches", 
              yscale = log10,
              title = "Bit length = $(nn*2)",
              xticks = (k_values, string.(k_values)))
    
    # Flatten data for MinGamma boxplot
    mingamma_x = Float64[]
    mingamma_y = Float64[]
    for k in k_values
        if haskey(mingamma_data[n_idx], k)
            for branch in mingamma_data[n_idx][k]
                push!(mingamma_x, k + offset_mingamma)
                push!(mingamma_y, Float64(branch))
            end
        end
    end
    
    # Flatten data for MostOcc boxplot
    mostocc_x = Float64[]
    mostocc_y = Float64[]
    for k in k_values
        if haskey(mostocc_data[n_idx], k)
            for branch in mostocc_data[n_idx][k]
                push!(mostocc_x, k + offset_mostocc)
                push!(mostocc_y, Float64(branch))
            end
        end
    end
    
    # Draw boxplots
    if !isempty(mingamma_y)
        boxplot!(ax, mingamma_x, mingamma_y; label = "MinGamma", width = 0.35, color = :steelblue)
    end
    if !isempty(mostocc_y)
        boxplot!(ax, mostocc_x, mostocc_y; label = "MostOcc", width = 0.35, color = :orange)
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

save("branch_selector_comparison(measure=NumHardTensors).png", fig)
fig
