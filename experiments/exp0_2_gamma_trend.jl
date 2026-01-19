"""
Experiment 0.2: Gamma vs Progress Trend

Shows the relationship between solving progress (current measure / initial measure)
and the current gamma value. Uses a 14x14 factoring instance.

Compares MinGammaSelector vs MostOccurrenceSelector to show how variable selection
affects the gamma landscape during solving.
"""

using BooleanInference
using OptimalBranchingCore
using CairoMakie
using Statistics
using Printf

"""
    run_with_traces(n, m, N, selector) -> (gamma_trace, measure_trace, stats)

Run solver with specified selector and return both gamma and measure traces.
"""
function run_with_traces(n::Int, m::Int, N::Int, selector::OptimalBranchingCore.AbstractSelector)
    bsconfig = BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=selector,
        measure=NumUnfixedTensors(),
        set_cover_solver=GreedyMerge()
    )

    a, b, stats = solve_factoring(n, m, N;
        bsconfig=bsconfig,
        reducer=NoReducer(),
        show_stats=false
    )

    return stats.gamma_trace, stats.measure_trace, stats
end

"""
    compute_progress(measure_trace) -> Vector{Float64}

Convert measure trace to progress (1 - current/initial).
Progress goes from 0 (start) to approaching 1 (near solution).
"""
function compute_progress(measure_trace::Vector{Float64})
    isempty(measure_trace) && return Float64[]
    initial = measure_trace[1]
    initial == 0 && return ones(length(measure_trace))
    return [1.0 - m / initial for m in measure_trace]
end

"""
    load_instance(file_path; instance_idx=1) -> NamedTuple

Load a specific factoring instance from data file.
"""
function load_instance(file_path::String; instance_idx::Int=1)
    lines = readlines(file_path)
    idx = 0

    for line in lines
        isempty(strip(line)) && continue

        parts = split(strip(line))
        length(parts) < 3 && continue

        idx += 1
        idx < instance_idx && continue

        n = parse(Int, parts[1])
        m = parse(Int, parts[2])
        N = parse(Int, parts[3])
        p = length(parts) >= 4 ? parse(Int, parts[4]) : 0
        q = length(parts) >= 5 ? parse(Int, parts[5]) : 0

        return (n=n, m=m, N=N, p=p, q=q, name="$(n)x$(m)_$(N)")
    end

    error("Instance $instance_idx not found in $file_path (only $idx instances)")
end

"""
    plot_gamma_vs_progress(gamma_trace, progress; output_path)

Plot gamma values against progress, with legend outside and under the plot.
"""
function plot_gamma_vs_progress(
    gamma_trace::Vector{Float64},
    progress::Vector{Float64};
    output_path::String="plots/exp0_2_gamma_trend"
)
    n = length(gamma_trace)
    @assert n == length(progress) "Traces must have same length"

    # Separate gamma=1 and gamma>1 points
    mask_branching = gamma_trace .> 1.0
    prog_branching = progress[mask_branching]
    gamma_branching = gamma_trace[mask_branching]

    # Colors
    color_reduction = (:steelblue, 0.7)
    color_branching = :firebrick

    # Figure dimensions (thinner, publication quality)
    fig = Figure(
        size = (200, 150),
        fontsize = 9,
        font = "Times New Roman",
        figure_padding = (4, 6, 4, 4)
    )

    ax = Axis(fig[1, 1],
        xlabel = "Progress",
        ylabel = L"\gamma",
        xlabelsize = 10,
        ylabelsize = 11,
        xticklabelsize = 8,
        yticklabelsize = 8,
        yticklabelrotation = pi/2,
        xticks = ([0, 0.5, 1.0], ["0%", "50%", "100%"]),
    )

    xlims!(ax, -0.02, 1.02)
    max_gamma = isempty(gamma_trace) ? 1.2 : maximum(gamma_trace)
    ylims!(ax, 0.98, max_gamma + 0.03)

    # Draw baseline at gamma=1
    hlines!(ax, [1.0], color=color_reduction, linewidth=1.5)

    # Draw vertical stems from gamma=1 to actual gamma for branching points
    for (p, g) in zip(prog_branching, gamma_branching)
        lines!(ax, [p, p], [1.0, g], color=(color_branching, 0.8), linewidth=1.5)
    end

    # Scatter markers at branching points
    scatter!(ax, prog_branching, gamma_branching,
        color=color_branching,
        markersize=5,
        marker=:circle
    )

    # Legend elements - placed outside and under the plot
    elem_reduction = [LineElement(color=color_reduction, linewidth=2)]
    elem_branching = [MarkerElement(color=color_branching, marker=:circle, markersize=6)]

    Legend(fig[2, 1],
        [elem_reduction, elem_branching],
        [L"\gamma=1", L"\gamma>1"],
        orientation = :horizontal,
        halign = :center,
        framevisible = false,
        labelsize = 8,
        padding = (0, 0, 0, 0),
        patchsize = (14, 8)
    )

    rowgap!(fig.layout, 4)

    # Ensure output directory exists
    outdir = dirname(output_path)
    !isempty(outdir) && mkpath(outdir)

    save("$(output_path).pdf", fig, pt_per_unit=1)
    save("$(output_path).png", fig, px_per_unit=4)
    println("Saved: $(output_path).pdf and $(output_path).png")

    return fig
end

"""
    run_exp0_2(; instance_idx=1, output_dir="plots")

Main experiment function. Compares MinGammaSelector vs MostOccurrenceSelector.
"""
function run_exp0_2(; instance_idx::Int=1, output_dir::String="plots")
    println("\n" * "="^70)
    println("Experiment 0.2: Gamma vs Progress Trend")
    println("="^70)

    # Load 14x14 instance
    data_file = joinpath(@__DIR__, "../benchmarks/data/factoring/numbers_14x14.txt")
    inst = load_instance(data_file; instance_idx=instance_idx)

    println("\nInstance: $(inst.name)")
    println("  N = $(inst.N) = $(inst.p) x $(inst.q)")

    # Define selectors to compare
    selectors = [
        (name="MinGamma", selector=MinGammaSelector(3, 4, 0)),
        (name="MostOccurrence", selector=MostOccurrenceSelector(3, 4)),
    ]

    results = []

    for (sel_name, selector) in selectors
        println("\n--- $sel_name Selector ---")

        start_time = time()
        gamma_trace, measure_trace, stats = run_with_traces(inst.n, inst.m, inst.N, selector)
        elapsed = time() - start_time

        @printf("  Time: %.2fs\n", elapsed)
        @printf("  Trace length: %d decision points\n", length(gamma_trace))

        if isempty(gamma_trace) || isempty(measure_trace)
            println("  Warning: Empty traces - skipping plot")
            continue
        end

        # Compute progress
        progress = compute_progress(measure_trace)

        @printf("  Initial measure: %.0f\n", measure_trace[1])
        @printf("  Final measure: %.0f\n", measure_trace[end])
        @printf("  Progress range: %.2f%% to %.2f%%\n", progress[1]*100, progress[end]*100)

        # Gamma statistics
        @printf("  Min γ: %.4f\n", minimum(gamma_trace))
        @printf("  Max γ: %.4f\n", maximum(gamma_trace))
        @printf("  Avg γ: %.4f\n", mean(gamma_trace))
        @printf("  γ=1 ratio: %.1f%%\n", count(g -> g == 1.0, gamma_trace) / length(gamma_trace) * 100)

        # Node statistics
        println("  Node counts:")
        @printf("    branching_nodes: %d\n", stats.branching_nodes)
        @printf("    reduction_nodes: %d\n", stats.reduction_nodes)
        @printf("    terminal_nodes:  %d\n", stats.terminal_nodes)

        # Generate plot
        output_path = joinpath(output_dir, "exp0_2_gamma_trend_$(lowercase(sel_name))")
        fig = plot_gamma_vs_progress(gamma_trace, progress; output_path=output_path)

        push!(results, (
            name=sel_name,
            gamma_trace=gamma_trace,
            measure_trace=measure_trace,
            progress=progress,
            stats=stats
        ))
    end

    return results
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_exp0_2(output_dir=joinpath(@__DIR__, "plots"))
end
