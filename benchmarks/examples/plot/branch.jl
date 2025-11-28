using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))
using CairoMakie
using BooleanInferenceBenchmarks
using Statistics

result_dir = resolve_results_dir("factoring")

n = [10, 12, 14, 16, 18, 20]
branches_n = []
times_n = []

kissat_branches_n = []
kissat_times_n = []
minisat_branches_n = []
minisat_times_n = []
Gurobi_times_n = []

for nn in n
    results_nxn = load_dataset_results(result_dir, "numbers_$(nn)x$(nn)")
    bi_results = filter_results(results_nxn, solver_name="BI")

    # find least avg. branch number / time config
    least_avg_branch_value = Inf
    least_avg_branch_index = 0
    for (i, result) in enumerate(bi_results)
        if result.solver_config["selector_type"] == "MostOccurrenceSelector"
            if mean(result.branches) < least_avg_branch_value
                least_avg_branch_value = mean(result.branches)
                least_avg_branch_index = i
            end
        end
    end

    branches = bi_results[least_avg_branch_index].branches
    times = bi_results[least_avg_branch_index].times

    push!(branches_n, branches)
    push!(times_n, times)

    kissat_results = filter_results(results_nxn, solver_name="Kissat")
    minisat_results = filter_results(results_nxn, solver_name="MiniSAT")
    gurobi_results = filter_results(results_nxn, solver_name="IP-Gurobi")
    push!(kissat_branches_n, kissat_results[1].branches)
    push!(kissat_times_n, kissat_results[1].times)
    push!(minisat_branches_n, minisat_results[1].branches)
    push!(minisat_times_n, minisat_results[1].times)
    if length(gurobi_results) > 0
        push!(Gurobi_times_n, gurobi_results[1].times)
    end
end

begin
    # x-axis: n, y-axis: branches
    # show the boxplot of the branches and times
    fig = Figure(size = (1000, 500))

    # branches - flatten data for boxplot
    branches_x_bi = Float64[]
    branches_y_bi = Float64[]
    branches_x_kissat = Float64[]
    branches_y_kissat = Float64[]
    branches_x_minisat = Float64[]
    branches_y_minisat = Float64[]

    # Offset for side-by-side boxplots (3 solvers for branches)
    offset_bi = -0.35
    offset_kissat = 0.0
    offset_minisat = 0.35
    
    # Offset for side-by-side boxplots (4 solvers for times)
    offset_gurobi = -0.5
    offset_bi_time = -0.2
    offset_kissat_time = 0.5
    offset_minisat_time = 0.2
    

    for (i, nn) in enumerate(n)
        # BI branches (left)
        for branch in branches_n[i]
            push!(branches_x_bi, nn + offset_bi)
            push!(branches_y_bi, Float64(branch))
        end
        # Kissat branches (center)
        for branch in kissat_branches_n[i]
            push!(branches_x_kissat, nn + offset_kissat)
            push!(branches_y_kissat, Float64(branch))
        end
        # MiniSAT branches (right)
        for branch in minisat_branches_n[i]
            push!(branches_x_minisat, nn + offset_minisat)
            push!(branches_y_minisat, Float64(branch))
        end
    end

    ax1 = Axis(fig[1, 1], xlabel = "n", ylabel = "Branches", yscale = log10, 
            xticks = (n, string.(n)), title = "Branch Count Comparison")
    boxplot!(ax1, branches_x_bi, branches_y_bi; label = "BI", width = 0.35, color = :red)
    boxplot!(ax1, branches_x_kissat, branches_y_kissat; label = "Kissat", width = 0.35, color = :blue)
    boxplot!(ax1, branches_x_minisat, branches_y_minisat; label = "MiniSAT", width = 0.35, color = :green)

    # times - flatten data for boxplot
    times_x_bi = Float64[]
    times_y_bi = Float64[]
    times_x_kissat = Float64[]
    times_y_kissat = Float64[]
    times_x_minisat = Float64[]
    times_y_minisat = Float64[]
    times_x_gurobi = Float64[]
    times_y_gurobi = Float64[]

    for (i, nn) in enumerate(n)
        # BI times
        for time in times_n[i]
            push!(times_x_bi, nn + offset_bi_time)
            push!(times_y_bi, time)
        end
        # Kissat times
        for time in kissat_times_n[i]
            push!(times_x_kissat, nn + offset_kissat_time)
            push!(times_y_kissat, time)
        end
        # MiniSAT times
        for time in minisat_times_n[i]
            push!(times_x_minisat, nn + offset_minisat_time)
            push!(times_y_minisat, time)
        end
        # Gurobi times
        if i <= length(Gurobi_times_n)
            for time in Gurobi_times_n[i]
                push!(times_x_gurobi, nn + offset_gurobi)
                push!(times_y_gurobi, time)
            end
        end
    end

    ax2 = Axis(fig[1, 2], xlabel = "n", ylabel = "Time (s)", yscale = log10, 
            xticks = (n, string.(n)), title = "Time Comparison")
            boxplot!(ax2, times_x_gurobi, times_y_gurobi; label = "Gurobi", width = 0.35, color = :orange)
    boxplot!(ax2, times_x_bi, times_y_bi; label = "BI", width = 0.35, color = :red)
    boxplot!(ax2, times_x_kissat, times_y_kissat; label = "Kissat", width = 0.35, color = :blue)
    boxplot!(ax2, times_x_minisat, times_y_minisat; label = "MiniSAT", width = 0.45, color = :green)
    

    # Add shared legend (use ax2 since it has all 4 solvers)
    Legend(fig[2, 1:2], ax2, orientation = :horizontal, framevisible = false, nbanks = 1)

    save("branch_comparison.png", fig)
    fig
end