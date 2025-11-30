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
gurobi_times_n = []
xsat_times_n = []

for nn in n
    results_nxn = load_dataset_results(result_dir, "numbers_$(nn)x$(nn)")
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
    times = bi_results[least_avg_branch_index].times

    push!(branches_n, branches)
    push!(times_n, times)

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

# ==================== Figure 1: Branch Count Comparison ====================
begin
    fig1 = Figure(size = (450, 300))

    # Flatten data for boxplot
    branches_x_bi = Float64[]
    branches_y_bi = Float64[]
    branches_x_kissat = Float64[]
    branches_y_kissat = Float64[]
    branches_x_minisat = Float64[]
    branches_y_minisat = Float64[]

    # Offset for side-by-side boxplots (3 solvers)
    offset_bi = -0.4
    offset_kissat = 0.0
    offset_minisat = 0.4

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

    ax1 = Axis(fig1[1, 1], xlabel = "Bit length", ylabel = "Branches", yscale = log10, 
            xticks = (n, string.(2 .* n)), title = "Branch Count (CircuitSAT-Factoring)")
    boxplot!(ax1, branches_x_bi, branches_y_bi; label = "BI", width = 0.35, color = :red)
    boxplot!(ax1, branches_x_kissat, branches_y_kissat; label = "Kissat", width = 0.35, color = :blue)
    boxplot!(ax1, branches_x_minisat, branches_y_minisat; label = "MiniSAT", width = 0.35, color = :green)

    Legend(fig1[2, 1], ax1, orientation = :horizontal, framevisible = false, nbanks = 1)

    save("branch_comparison.png", fig1)
    fig1
end

# ==================== Figure 2: Time Comparison ====================
begin
    fig2 = Figure(size = (800, 500))

    # Flatten data for boxplot
    times_x_bi = Float64[]
    times_y_bi = Float64[]
    times_x_kissat = Float64[]
    times_y_kissat = Float64[]
    times_x_minisat = Float64[]
    times_y_minisat = Float64[]
    times_x_gurobi = Float64[]
    times_y_gurobi = Float64[]
    times_x_xsat = Float64[]
    times_y_xsat = Float64[]

    # Offset for side-by-side boxplots (5 solvers)
    offset_gurobi = -0.6
    offset_xsat = 0.0
    offset_bi_time = -0.3
    offset_kissat_time = 0.6
    offset_minisat_time = 0.3

    for (i, nn) in enumerate(n)
        for time in times_n[i]
            push!(times_x_bi, nn + offset_bi_time)
            push!(times_y_bi, time)
        end
        for time in kissat_times_n[i]
            push!(times_x_kissat, nn + offset_kissat_time)
            push!(times_y_kissat, time)
        end
        for time in minisat_times_n[i]
            push!(times_x_minisat, nn + offset_minisat_time)
            push!(times_y_minisat, time)
        end
        for time in gurobi_times_n[i]
            push!(times_x_gurobi, nn + offset_gurobi)
            push!(times_y_gurobi, time)
        end
        for time in xsat_times_n[i]
            push!(times_x_xsat, nn + offset_xsat)
            push!(times_y_xsat, time)
        end
    end

    ax2 = Axis(fig2[1, 1], xlabel = "Bit length", ylabel = "Time (s)", yscale = log10, 
            xticks = (n, string.(2 .* n)), title = "Time Comparison")
    boxplot!(ax2, times_x_gurobi, times_y_gurobi; label = "Gurobi", width = 0.25, color = :orange)
    boxplot!(ax2, times_x_xsat, times_y_xsat; label = "X-SAT", width = 0.25, color = :purple)
    boxplot!(ax2, times_x_bi, times_y_bi; label = "BI", width = 0.25, color = :red)
    boxplot!(ax2, times_x_kissat, times_y_kissat; label = "Kissat", width = 0.25, color = :blue)
    boxplot!(ax2, times_x_minisat, times_y_minisat; label = "MiniSAT", width = 0.25, color = :green)

    Legend(fig2[2, 1], ax2, orientation = :horizontal, framevisible = false, nbanks = 1)

    save("time_comparison.png", fig2)
    fig2
end
