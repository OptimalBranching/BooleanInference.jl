using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
using CairoMakie
using BooleanInferenceBenchmarks
using Statistics
using JSON3

# Function to parse clause-to-variable ratio from directory name
function parse_ratio(dirname)
    parts = split(dirname, '-')
    n_vars = parse(Int, parts[1])
    n_clauses = parse(Int, parts[2])
    return n_clauses / n_vars
end

# Function to load results from a directory
function load_results_from_dir(base_dir, dir_name)
    dir_path = joinpath(base_dir, dir_name)
    results = []
    
    if isdir(dir_path)
        for file in readdir(dir_path)
            if endswith(file, ".json")
                file_path = joinpath(dir_path, file)
                result = JSON3.read(read(file_path, String))
                push!(results, result)
            end
        end
    end
    
    return results
end

# Base directory for CNFSAT results
result_dir = resolve_results_dir("CNFSAT")

n_values = [100]
n = [350, 380, 400, 420, 430, 450]
k_values = [1, 2, 3, 4, 5]

branches_n = []
kissat_branches_n = []
minisat_branches_n = []

for nn in n
    results_nxn = load_dataset_results(result_dir, "100-$(nn)")
    bi_results = filter_results(results_nxn, solver_name="BI")

    # find least avg. branch number config for MostOccurrenceSelector
    least_avg_branch_value = Inf
    least_avg_branch_index = 0
    for (i, result) in enumerate(bi_results)
        if result.solver_config["selector_type"] == "MostOccurrenceSelector" && result.solver_config["measure"] == "NumHardTensors"
            if mean(result.branches) < least_avg_branch_value
                least_avg_branch_value = mean(result.branches)
                least_avg_branch_index = i
            end
        end
    end

    branches = bi_results[least_avg_branch_index].branches

    push!(branches_n, branches)

    kissat_results = filter_results(results_nxn, solver_name="Kissat")
    minisat_results = filter_results(results_nxn, solver_name="MiniSAT")
    gurobi_results = filter_results(results_nxn, solver_name="IP-Gurobi")
    xsat_results = filter_results(results_nxn, solver_name="X-SAT")
    
    push!(kissat_branches_n, !isempty(kissat_results) ? kissat_results[1].branches : Int[])
    push!(minisat_branches_n, !isempty(minisat_results) ? minisat_results[1].branches : Int[])

end

n = [3.5, 3.8, 4.0, 4.2, 4.3, 4.5]
begin
    fig1 = Figure(size = (450, 300), backgroundcolor = :transparent)

    # Flatten data for boxplot
    branches_x_bi = Float64[]
    branches_y_bi = Float64[]
    branches_x_kissat = Float64[]
    branches_y_kissat = Float64[]
    branches_x_minisat = Float64[]
    branches_y_minisat = Float64[]

    # Offset for side-by-side boxplots (3 solvers)
    offset_bi = -0.025
    offset_kissat = 0.0
    offset_minisat = 0.025

    for (i, nn) in enumerate(n)
        for branch in branches_n[i]
            push!(branches_x_bi, nn + offset_bi)
            push!(branches_y_bi, Float64(branch))
        end
        for branch in kissat_branches_n[i]
            push!(branches_x_kissat, nn + offset_kissat)
            push!(branches_y_kissat, Float64(branch))
        end
        for branch in minisat_branches_n[i]
            push!(branches_x_minisat, nn + offset_minisat)
            push!(branches_y_minisat, Float64(branch))
        end
    end

    ax1 = Axis(fig1[1, 1],
        xlabel = "Clause-Variable Ratio",
        ylabel = "Branches",
        yscale = log10,
        xticks = (n, string.(n)),
        title = "Branch Count (Random 3-SAT)",
        backgroundcolor = :transparent,
    )
    boxplot!(ax1, branches_x_bi, branches_y_bi; label = "BI", width = 0.03, color = :red)
    boxplot!(ax1, branches_x_kissat, branches_y_kissat; label = "Kissat", width = 0.03, color = :blue)
    boxplot!(ax1, branches_x_minisat, branches_y_minisat; label = "MiniSAT", width = 0.03, color = :green)

    Legend(fig1[2, 1], ax1, orientation = :horizontal, framevisible = false, nbanks = 1)

    save("branch_comparison_3sat.png", fig1)
    fig1
end


save("notes/temp/cnfsat_branch_comparison.png", fig1)
fig1
