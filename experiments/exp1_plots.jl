"""
Experiment 1 Visualization: Generate all plots for Exp 1

Figures to generate:
- Figure 1 (Exp 1.1): Branching rule comparison table + bar chart
- Figure 2 (Exp 1.2): Region selector Pareto frontier
- Figure 3 (Exp 1.4): Region size heatmap
"""

include("exp1_utils.jl")

using CairoMakie
using DataFrames
using Statistics
using Printf

"""
    plot_exp1_1_branching_comparison(results_file::String; output_file::String="exp1_1_plot.pdf")

Generate bar chart comparing branching rules (DPLL vs NaiveBranch vs GreedyMerge)
"""
function plot_exp1_1_branching_comparison(results_file::String; output_file::String="exp1_1_plot.pdf")
    # Load results
    results = load_results(results_file)
    df = results_to_dataframe(results)

    # Compute summary statistics by config
    summary = combine(groupby(df, :config),
        :time => median => :median_time,
        :branching_nodes => sum => :total_branching_nodes,
        :children_explored => sum => :total_children_explored,
        :avg_gamma => mean => :mean_gamma
    )

    # Sort by method order (DPLL, NaiveBranch, GreedyMerge)
    method_order = ["DPLL", "NaiveBranch", "GreedyMerge", "GreedyMerge+GammaOptimized"]
    sort!(summary, :config, by = x -> begin
        idx = findfirst(==(x), method_order)
        idx === nothing ? length(method_order) + 1 : idx
    end)

    # Create color mapping - convert config to strings for xticks compatibility
    config_strings = String.(summary.config)
    colors_map = Dict("DPLL" => :red, "NaiveBranch" => :orange, "GreedyMerge" => :green, "GreedyMerge+GammaOptimized" => :blue)
    colors_list = [Base.get(colors_map, cfg, :gray) for cfg in config_strings]

    # Create figure with 2x2 subplots
    fig = Figure(size=(1200, 900), fontsize=14)

    # Plot 1: Median solve time
    ax1 = Axis(fig[1, 1],
        xlabel="Branching Method",
        ylabel="Median Solve Time (s)",
        title="(a) Solve Time Comparison",
        xticks=(1:nrow(summary), config_strings)
    )
    barplot!(ax1, 1:nrow(summary), summary.median_time,
        color=colors_list,
        strokewidth=1,
        strokecolor=:black
    )

    # Plot 2: Total branches
    ax2 = Axis(fig[1, 2],
        xlabel="Branching Method",
        ylabel="Total Branches",
        title="(b) Search Tree Size",
        xticks=(1:nrow(summary), config_strings)
    )
    barplot!(ax2, 1:nrow(summary), summary.total_children_explored,
        color=colors_list,
        strokewidth=1,
        strokecolor=:black
    )

    # Plot 3: Mean gamma
    ax3 = Axis(fig[2, 1],
        xlabel="Branching Method",
        ylabel="Average Branching Factor γ",
        title="(c) Branching Factor",
        xticks=(1:nrow(summary), config_strings)
    )
    barplot!(ax3, 1:nrow(summary), summary.mean_gamma,
        color=colors_list,
        strokewidth=1,
        strokecolor=:black
    )
    hlines!(ax3, [2.0], color=:black, linestyle=:dash, label="DPLL baseline (γ=2.0)")
    axislegend(ax3, position=:rt)

    # Plot 4: Per-instance solve time comparison
    ax4 = Axis(fig[2, 2],
        xlabel="Instance",
        ylabel="Solve Time (s)",
        title="(d) Per-Instance Performance",
        xticks=(1:10, string.(1:10))
    )

    # Get data for each method
    instances = unique(df.instance)
    x_positions = 1:length(instances)

    # Get all methods that exist in the data
    available_methods = String.(unique(df.config))
    
    for (i, method) in enumerate(available_methods)
        method_df = filter(r -> String(r.config) == method, df)
        # Handle missing data: only include instances that have data for this method
        times = Float64[]
        x_pos = Float64[]
        for (j, inst) in enumerate(instances)
            inst_data = filter(r -> r.instance == inst, method_df)
            if nrow(inst_data) > 0
                push!(times, inst_data.time[1])
                push!(x_pos, j + (i-2)*0.2)
            end
        end
        if length(times) > 0
            scatter!(ax4, x_pos, times,
                label=method,
                markersize=10,
                color=Base.get(colors_map, method, :gray)
            )
        end
    end
    axislegend(ax4, position=:rt)

    # Add overall title
    Label(fig[0, :], "Experiment 1.1: Branching Rule Quality Comparison",
        fontsize=18, font=:bold)

    # Save figure
    save(output_file, fig)
    println("Saved plot to $output_file")

    return fig
end

"""
    plot_exp1_2_selector_pareto(results_file::String; output_file::String="exp1_2_plot.pdf")

Generate Pareto frontier plot for region selectors (paper-quality)
"""
function plot_exp1_2_selector_pareto(results_file::String; output_file::String="exp1_2_plot.pdf")
    # Load results
    results = load_results(results_file)
    df = results_to_dataframe(results)

    # Compute summary statistics by config
    summary = combine(groupby(df, :config),
        :time => median => :median_time,
        :avg_gamma => mean => :mean_gamma,
        :terminal_nodes => sum => :total_terminal_nodes
    )

    # Paper-quality: tight single-column figure with Times New Roman
    fig = Figure(
        size=(235, 375),
        fontsize=11,
        font="Times New Roman",
        figure_padding=(4, 6, 4, 4)
    )

    ax = Axis(fig[1, 1],
        xlabel="Time (s)",
        ylabel="#Leaf nodes",
        xscale=log10,
        yscale=log10,
        xlabelsize=11,
        ylabelsize=11,
        xticklabelsize=9,
        yticklabelsize=9,
        yticklabelrotation=π/2
    )

    summary.config_str = String.(summary.config)
    times = Vector{Float64}(summary.median_time)
    leaves = Vector{Float64}(summary.total_terminal_nodes)

    # Pareto frontier (minimize both)
    function pareto_frontier_idxs(t::Vector{<:Real}, l::Vector{<:Real})
        n = length(t)
        keep = trues(n)
        @inbounds for i in 1:n
            for j in 1:n
                i == j && continue
                if (t[j] <= t[i]) && (l[j] <= l[i]) && ((t[j] < t[i]) || (l[j] < l[i]))
                    keep[i] = false
                    break
                end
            end
        end
        idxs = findall(keep)
        return idxs[sortperm(t[idxs])]
    end

    function selector_family(cfg::AbstractString)
        # Order matters: check more specific patterns first
        startswith(cfg, "MostOccurrence+OB") && return "MostOccurrence+OB"
        startswith(cfg, "MostOccurrence") && return "MostOccurrence"
        startswith(cfg, "Lookahead+OB") && return "Lookahead+OB"
        startswith(cfg, "MinGamma") && return "MinGamma"
        return "Other"
    end

    # Darker/more saturated color palette
    fam_colors = Dict(
        "MostOccurrence"    => "#A01A58",  # dark magenta
        "MostOccurrence+OB" => "#C54500",  # dark orange
        "MinGamma"          => "#0066AA",  # dark blue
        "Lookahead+OB"      => "#006B45",  # dark teal
        "Other"             => "#555555"
    )
    fam_markers = Dict(
        "MostOccurrence"    => :xcross,
        "MostOccurrence+OB" => :circle,
        "MinGamma"          => :rect,
        "Lookahead+OB"      => :utriangle,
        "Other"             => :cross
    )

    # Compute Pareto frontier first
    frontier = pareto_frontier_idxs(times, leaves)
    frontier_set = Set(frontier)

    # Assign family to each point
    fam_vec = [selector_family(c) for c in summary.config_str]

    # Fixed order for legend: MostOccurrence, MostOccurrence+OB, Lookahead+OB, MinGamma
    family_order = ["MostOccurrence", "MostOccurrence+OB", "Lookahead+OB", "MinGamma"]

    # Plot all points by family (in order), distinguishing frontier vs non-frontier
    for fam in family_order
        fam_idxs = findall(==(fam), fam_vec)
        isempty(fam_idxs) && continue

        non_frontier_idxs = filter(i -> !(i in frontier_set), fam_idxs)
        frontier_idxs = filter(i -> i in frontier_set, fam_idxs)

        col = Base.get(fam_colors, fam, "#999999")
        mrk = Base.get(fam_markers, fam, :circle)

        # Non-frontier points (same color, no border)
        if !isempty(non_frontier_idxs)
            scatter!(ax, times[non_frontier_idxs], leaves[non_frontier_idxs],
                color=col,
                marker=mrk,
                markersize=8,
                strokewidth=0
            )
        end

        # Frontier points (same color, with black border) - these add the label
        if !isempty(frontier_idxs)
            scatter!(ax, times[frontier_idxs], leaves[frontier_idxs],
                color=col,
                marker=mrk,
                markersize=10,
                strokewidth=1.5,
                strokecolor=:black,
                label=fam
            )
        else
            # No frontier points for this family - add a dummy for legend only
            scatter!(ax, Float64[], Float64[],
                color=col,
                marker=mrk,
                markersize=10,
                strokewidth=1.5,
                strokecolor=:black,
                label=fam
            )
        end
    end

    # Pareto frontier: dashed line only
    lines!(ax, times[frontier], leaves[frontier],
        color=:black, linewidth=1.0, linestyle=:dash)

    # Legend: top-right inside
    axislegend(ax, position=:rt, framevisible=false, labelsize=8, rowgap=0, patchsize=(10, 10))

    # Fix tick labels for log scale
    ax.xticks = [0.1, 0.2, 0.5, 1, 2, 5]
    ax.yticks = [100, 200, 500, 1000, 2000, 5000, 10000]
    ax.ytickformat = values -> [string(Int(round(v))) for v in values]

    save(output_file, fig)
    println("Saved plot to $output_file")
    return fig
end

"""
    plot_exp1_4_region_size_heatmap(results_file::String; output_file::String="exp1_4_plot.pdf")

Generate heatmap showing region size trade-offs
"""
function plot_exp1_4_region_size_heatmap(results_file::String; output_file::String="exp1_4_plot.pdf")
    # Load results
    results = load_results(results_file)
    df = results_to_dataframe(results)

    # Parse k and max_tensors from config name (format: "k3_mt4")
    df.k = [parse(Int, match(r"k(\d+)", c).captures[1]) for c in df.config]
    df.max_tensors = [parse(Int, match(r"mt(\d+)", c).captures[1]) for c in df.config]

    # Compute median time for each configuration
    summary = combine(groupby(df, [:k, :max_tensors]),
        :time => median => :median_time,
        :avg_gamma => mean => :mean_gamma,
        :children_explored => mean => :mean_branches_explored
    )

    # Create pivot tables for heatmaps
    k_vals = sort(unique(summary.k))
    mt_vals = sort(unique(summary.max_tensors))

    # Time matrix
    time_matrix = zeros(length(mt_vals), length(k_vals))
    gamma_matrix = zeros(length(mt_vals), length(k_vals))

    for row in eachrow(summary)
        k_idx = findfirst(==(row.k), k_vals)
        mt_idx = findfirst(==(row.max_tensors), mt_vals)
        time_matrix[mt_idx, k_idx] = row.median_time
        gamma_matrix[mt_idx, k_idx] = row.mean_gamma
    end

    # Create figure with 2 heatmaps
    fig = Figure(size=(1200, 500), fontsize=14)

    # Heatmap 1: Solve time
    ax1 = Axis(fig[1, 1],
        xlabel="k (neighborhood radius)",
        ylabel="max_tensors",
        title="(a) Median Solve Time (s)",
        xticks=(1:length(k_vals), string.(k_vals)),
        yticks=(1:length(mt_vals), string.(mt_vals))
    )

    hm1 = heatmap!(ax1, time_matrix,
        colormap=:viridis,
        colorrange=(minimum(time_matrix), maximum(time_matrix))
    )
    Colorbar(fig[1, 2], hm1, label="Time (s)")

    # Add text annotations
    for i in 1:length(k_vals), j in 1:length(mt_vals)
        text!(ax1, i, j,
            text=@sprintf("%.1f", time_matrix[j, i]),
            align=(:center, :center),
            color=:white,
            fontsize=12
        )
    end

    # Heatmap 2: Average gamma
    ax2 = Axis(fig[1, 3],
        xlabel="k (neighborhood radius)",
        ylabel="max_tensors",
        title="(b) Average Branching Factor γ",
        xticks=(1:length(k_vals), string.(k_vals)),
        yticks=(1:length(mt_vals), string.(mt_vals))
    )

    hm2 = heatmap!(ax2, gamma_matrix,
        colormap=:plasma,
        colorrange=(minimum(gamma_matrix), maximum(gamma_matrix))
    )
    Colorbar(fig[1, 4], hm2, label="γ")

    # Add text annotations
    for i in 1:length(k_vals), j in 1:length(mt_vals)
        text!(ax2, i, j,
            text=@sprintf("%.2f", gamma_matrix[j, i]),
            align=(:center, :center),
            color=:white,
            fontsize=12
        )
    end

    # Add overall title
    Label(fig[0, :], "Experiment 1.4: Region Size Parameter Sweep",
        fontsize=18, font=:bold)

    # Save figure
    save(output_file, fig)
    println("Saved plot to $output_file")

    return fig
end

"""
    plot_exp1_3_measure_comparison(results_file::String; output_file::String="exp1_3_plot.pdf")

Generate comparison plot for measure functions
"""
function plot_exp1_3_measure_comparison(results_file::String; output_file::String="exp1_3_plot.pdf")
    # Load results
    results = load_results(results_file)
    df = results_to_dataframe(results)

    # Compute summary statistics by config
    summary = combine(groupby(df, :config),
        :time => median => :median_time,
        :avg_gamma => mean => :mean_gamma,
        :children_explored => sum => :total_children_explored
    )

    # Convert config to strings
    config_strings = String.(summary.config)

    # Create figure
    fig = Figure(size=(1000, 400), fontsize=14)

    # Plot 1: Solve time
    ax1 = Axis(fig[1, 1],
        xlabel="Measure Function",
        ylabel="Median Solve Time (s)",
        title="(a) Solve Time",
        xticks=(1:nrow(summary), config_strings)
    )
    barplot!(ax1, 1:nrow(summary), summary.median_time,
        color=[:blue, :orange],
        strokewidth=1,
        strokecolor=:black
    )

    # Plot 2: Average gamma
    ax2 = Axis(fig[1, 2],
        xlabel="Measure Function",
        ylabel="Average γ",
        title="(b) Branching Factor",
        xticks=(1:nrow(summary), config_strings)
    )
    barplot!(ax2, 1:nrow(summary), summary.mean_gamma,
        color=[:blue, :orange],
        strokewidth=1,
        strokecolor=:black
    )

    # Plot 3: Total branches
    ax3 = Axis(fig[1, 3],
        xlabel="Measure Function",
        ylabel="Total Branches",
        title="(c) Search Tree Size",
        xticks=(1:nrow(summary), config_strings)
    )
    barplot!(ax3, 1:nrow(summary), summary.total_children_explored,
        color=[:blue, :orange],
        strokewidth=1,
        strokecolor=:black
    )

    # Add overall title
    Label(fig[0, :], "Experiment 1.3: Measure Function Comparison",
        fontsize=18, font=:bold)

    # Save figure
    save(output_file, fig)
    println("Saved plot to $output_file")

    return fig
end

"""
    generate_all_exp1_plots(results_dir::String="results"; output_dir::String="plots")

Generate all Experiment 1 plots
"""
function generate_all_exp1_plots(results_dir::String="results"; output_dir::String="plots")
    println("\n" * "="^80)
    println("Generating all Experiment 1 plots")
    println("="^80)

    # Create output directory if needed
    mkpath(output_dir)

    # Generate plots for each experiment
    experiments = [
        ("exp1_1_branching_rules", plot_exp1_1_branching_comparison),
        ("exp1_2_region_selectors", plot_exp1_2_selector_pareto),
        ("exp1_3_measure_functions", plot_exp1_3_measure_comparison),
        ("exp1_4_region_size", plot_exp1_4_region_size_heatmap),
    ]

    for (exp_name, plot_func) in experiments
        results_file = joinpath(results_dir, exp_name)
        output_file = joinpath(output_dir, exp_name * ".pdf")

        if isfile(results_file * ".json")
            println("\nGenerating plot for $exp_name...")
            try
                plot_func(results_file; output_file=output_file)
                println("✓ Saved to $output_file")
            catch e
                @warn "Failed to generate plot for $exp_name" exception=e
            end
        else
            @warn "Results file not found: $(results_file).json"
        end
    end

    println("\n" * "="^80)
    println("All plots generated in $output_dir")
    println("="^80)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    generate_all_exp1_plots("results", "plots")
end
