"""
Experiment 0: γ-Landscape Visualization

Demonstrates that factoring instances exhibit a striking γ-landscape with:
- Long plateaus at γ = 1 (reduction phases)
- Brief spikes where min γ > 1 (saturation points)

Uses MinGammaSelector on 12x12 factoring instances.
"""

using BooleanInference
using OptimalBranchingCore
using CSV
using CairoMakie
using DataFrames
using Statistics
using Printf

"""
    run_gamma_trace(n, m, N; limit=0) -> (gamma_trace, stats)

Run MinGamma solver and return the γ-trace.
"""
function run_gamma_trace(n::Int, m::Int, N::Int; limit::Int=0)
    bsconfig = BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MinGammaSelector(3, 4, limit),
        measure=NumUnfixedTensors(),
        set_cover_solver=GreedyMerge()
    )

    a, b, stats = solve_factoring(n, m, N;
        bsconfig=bsconfig,
        reducer=NoReducer(),
        show_stats=false
    )

    return stats.gamma_trace, stats
end

"""
    analyze_gamma_trace(trace) -> NamedTuple

Compute statistics about a γ-trace.
"""
function analyze_gamma_trace(trace::Vector{Float64})
    isempty(trace) && return (
        length=0, gamma_1_ratio=0.0, gamma_1_runs=0,
        avg_spike_height=0.0, max_gamma=0.0, num_spikes=0
    )

    n = length(trace)
    gamma_1_count = count(g -> g == 1.0, trace)
    gamma_1_ratio = gamma_1_count / n

    # Count runs of γ=1
    gamma_1_runs = 0
    in_run = false
    for g in trace
        if g == 1.0 && !in_run
            gamma_1_runs += 1
            in_run = true
        elseif g != 1.0
            in_run = false
        end
    end

    # Analyze spikes (γ > 1)
    spikes = filter(g -> g > 1.0, trace)
    num_spikes = length(spikes)
    avg_spike_height = isempty(spikes) ? 0.0 : mean(spikes)
    max_gamma = maximum(trace)

    return (
        length=n,
        gamma_1_ratio=gamma_1_ratio,
        gamma_1_runs=gamma_1_runs,
        avg_spike_height=avg_spike_height,
        max_gamma=max_gamma,
        num_spikes=num_spikes
    )
end

"""
    ascii_plot_gamma(trace; width=80, height=15)

Create a simple ASCII visualization of the γ-trace.
Shows the "landscape" with plateaus and spikes.
"""
function ascii_plot_gamma(trace::Vector{Float64}; width::Int=80, height::Int=15, title::String="")
    isempty(trace) && return

    n = length(trace)
    max_g = max(maximum(trace), 2.0)  # At least show up to 2.0

    # Downsample if trace is longer than width
    if n > width
        step = n / width
        sampled = Float64[]
        for i in 1:width
            start_idx = max(1, floor(Int, (i-1) * step) + 1)
            end_idx = min(n, floor(Int, i * step))
            push!(sampled, maximum(trace[start_idx:end_idx]))
        end
        trace_plot = sampled
    else
        trace_plot = trace
    end

    plot_width = length(trace_plot)

    # Print title
    if !isempty(title)
        println("\n", title)
        println("=" ^ min(length(title), 60))
    end

    # Create plot
    println("\nγ")
    for row in height:-1:1
        threshold = (row / height) * max_g
        line = row == height ? @sprintf("%4.1f │", max_g) :
               row == 1 ? "1.00 │" : "     │"

        for g in trace_plot
            if g >= threshold
                if g == 1.0 && threshold <= 1.0
                    line *= "─"  # Plateau at γ=1
                else
                    line *= "█"  # Spike
                end
            else
                line *= " "
            end
        end
        println(line)
    end

    # X-axis
    println("     └" * "─"^plot_width)
    println("      0" * " "^(plot_width-8) * "step $(n)")

    # Legend
    println("\n  ─ = γ=1 (reduction)  █ = γ>1 (branching)")
end

"""
    save_gamma_traces(results, output_path)

Save γ-traces to CSV files for external plotting.
"""
function save_gamma_traces(results::Vector, output_path::String)
    mkpath(dirname(output_path))

    # Save individual traces
    for (i, r) in enumerate(results)
        trace_df = DataFrame(step=1:length(r.trace), gamma=r.trace)
        CSV.write("$(output_path)_trace_$(i)_$(r.name).csv", trace_df)
    end

    # Save summary statistics
    summary_df = DataFrame(
        instance = [r.name for r in results],
        N = [r.N for r in results],
        trace_length = [r.analysis.length for r in results],
        gamma_1_ratio = [r.analysis.gamma_1_ratio for r in results],
        gamma_1_runs = [r.analysis.gamma_1_runs for r in results],
        num_spikes = [r.analysis.num_spikes for r in results],
        avg_spike_height = [r.analysis.avg_spike_height for r in results],
        max_gamma = [r.analysis.max_gamma for r in results],
        solve_time = [r.time for r in results]
    )
    CSV.write("$(output_path)_summary.csv", summary_df)

    println("\nSaved traces to $(output_path)_trace_*.csv")
    println("Saved summary to $(output_path)_summary.csv")
end

"""
    load_instances(file_path; max_instances=5)

Load factoring instances from data file.
"""
function load_instances(file_path::String; max_instances::Int=5)
    instances = []
    open(file_path, "r") do f
        for (i, line) in enumerate(eachline(f))
            i > max_instances && break
            isempty(strip(line)) && continue

            parts = split(strip(line))
            length(parts) < 3 && continue

            n = parse(Int, parts[1])
            m = parse(Int, parts[2])
            N = parse(Int, parts[3])
            p = length(parts) >= 4 ? parse(Int, parts[4]) : 0
            q = length(parts) >= 5 ? parse(Int, parts[5]) : 0

            name = "$(n)x$(m)_$(N)"
            push!(instances, (n=n, m=m, N=N, p=p, q=q, name=name))
        end
    end
    return instances
end

"""
    run_exp0(; max_instances=5, output_dir="results", show_plots=true)

Main experiment function.
"""
function run_exp0(; max_instances::Int=5, output_dir::String="results", show_plots::Bool=true)
    println("\n" * "="^70)
    println("Experiment 0: γ-Landscape Visualization")
    println("="^70)

    data_file = joinpath(@__DIR__, "../benchmarks/data/factoring/numbers_14x14.txt")

    # Load instances
    instances = load_instances(data_file; max_instances=max_instances)
    println("\nLoaded $(length(instances)) instances from 14x14 dataset")

    # Run experiments
    results = []

    for (idx, inst) in enumerate(instances)
        println("\n[$(idx)/$(length(instances))] Instance: $(inst.name)")
        println("  N = $(inst.N) = $(inst.p) × $(inst.q)")

        start_time = time()
        trace, stats = run_gamma_trace(inst.n, inst.m, inst.N)
        elapsed = time() - start_time

        analysis = analyze_gamma_trace(trace)

        push!(results, (
            name=inst.name,
            N=inst.N,
            trace=trace,
            stats=stats,
            analysis=analysis,
            time=elapsed
        ))

        # Print summary
        @printf("  Time: %.2fs, Trace length: %d\n", elapsed, analysis.length)
        @printf("  γ=1 ratio: %.1f%% (%d runs), Spikes: %d (avg=%.2f, max=%.2f)\n",
            analysis.gamma_1_ratio * 100,
            analysis.gamma_1_runs,
            analysis.num_spikes,
            analysis.avg_spike_height,
            analysis.max_gamma)

        # Show ASCII plot
        if show_plots
            ascii_plot_gamma(trace; title="$(inst.name): γ-landscape")
        end
    end

    # Print aggregate statistics
    println("\n" * "="^70)
    println("Aggregate Statistics")
    println("="^70)

    avg_gamma_1_ratio = mean([r.analysis.gamma_1_ratio for r in results])
    avg_num_spikes = mean([r.analysis.num_spikes for r in results])
    avg_spike_height = mean([r.analysis.avg_spike_height for r in results])

    @printf("\nAverage γ=1 ratio: %.1f%%\n", avg_gamma_1_ratio * 100)
    @printf("Average number of spikes: %.1f\n", avg_num_spikes)
    @printf("Average spike height: %.2f\n", avg_spike_height)

    # Save results
    output_path = joinpath(output_dir, "exp0_gamma_landscape")
    mkpath(output_dir)
    save_gamma_traces(results, output_path)

    return results
end

# Plotting helper for external tools
"""
    generate_plot_script(output_path)

Generate a simple Python/matplotlib script for plotting.
"""
function generate_plot_script(output_path::String)
    script = """
import pandas as pd
import matplotlib.pyplot as plt
import glob

# Load all trace files
trace_files = sorted(glob.glob('$(output_path)_trace_*.csv'))

fig, axes = plt.subplots(len(trace_files), 1, figsize=(12, 3*len(trace_files)), sharex=False)
if len(trace_files) == 1:
    axes = [axes]

for ax, f in zip(axes, trace_files):
    df = pd.read_csv(f)
    name = f.split('_')[-1].replace('.csv', '')

    # Plot with different colors for γ=1 vs γ>1
    ax.fill_between(df['step'], 1, df['gamma'], where=df['gamma']>1,
                    alpha=0.7, color='red', label='γ>1 (saturation)')
    ax.axhline(y=1, color='blue', linestyle='-', alpha=0.5, label='γ=1 (reduction)')
    ax.plot(df['step'], df['gamma'], 'k-', linewidth=0.5)

    ax.set_ylabel('γ')
    ax.set_title(f'γ-landscape: {name}')
    ax.legend(loc='upper right')
    ax.set_ylim(0.9, max(df['gamma'].max() * 1.1, 2.5))

axes[-1].set_xlabel('Step')
plt.tight_layout()
plt.savefig('$(output_path)_plot.png', dpi=150)
plt.savefig('$(output_path)_plot.pdf')
print(f'Saved plot to $(output_path)_plot.png/pdf')
plt.show()
"""

    script_path = "$(output_path)_plot.py"
    open(script_path, "w") do f
        write(f, script)
    end
    println("Generated plotting script: $(script_path)")
    println("Run with: python $(script_path)")
end

# ============================================================================
# Publication-quality plotting with CairoMakie
# ============================================================================

"""
    plot_gamma_landscape(results; output_path="gamma_landscape", format=:pdf)

Generate a single γ-landscape figure (no subplots or insets).
"""
function plot_gamma_landscape(
    results::Vector;
    output_path::String="gamma_landscape",
    format::Symbol=:pdf,
    single_column::Bool=true
)
    # Lazy load CairoMakie
    @eval using CairoMakie

    # IJCAI figure dimensions (inches -> points, 72 pt/inch)
    # Single column: 3.25", Double column: 6.875"
    width_inch = single_column ? 3.25 : 6.875
    height_inch = 2.0

    width_pt = width_inch * 72
    height_pt = height_inch * 72

    # Create figure with publication settings
    fig = Figure(
        size = (width_pt, height_pt),
        fontsize = 8,
        font = "Times New Roman",
        figure_padding = (4, 4, 4, 4)
    )

    # Color scheme (colorblind-friendly)
    color_reduction = (:royalblue, 0.8)
    color_saturation = (:firebrick, 0.85)
    color_line = (:black, 0.6)

    r = results[1]
    trace = r.trace
    n = length(trace)
    steps = 1:n

    y_upper = maximum(trace) + 0.03

    ax = Axis(fig[1, 1],
        ylabel = L"\gamma",
        xlabel = "Decision step",
        title = "Instance: N = $(r.N)",
        titlesize = 8,
        xlabelsize = 8,
        ylabelsize = 9,
        xticklabelsize = 7,
        yticklabelsize = 7,
        yticklabelrotation = pi/2,
        titlefont = "Times New Roman",
        xticks = LinearTicks(4),
        yticks = [1.0, 1.1, 1.2],
        yminorticksvisible = false,
        xminorticksvisible = false,
    )

    ylims!(ax, 0.995, y_upper)
    xlims!(ax, 0, n + 1)

    # Draw γ=1 baseline
    hlines!(ax, [1.0], color=color_reduction, linewidth=1.5, linestyle=:solid)

    # Find and highlight saturation regions (γ > 1)
    in_spike = false
    spike_start = 0
    for j in 1:n
        if trace[j] > 1.0 && !in_spike
            spike_start = j
            in_spike = true
        elseif trace[j] == 1.0 && in_spike
            spike_x = spike_start:j-1
            spike_y = trace[spike_start:j-1]
            band!(ax, collect(spike_x), fill(1.0, length(spike_x)), spike_y,
                  color=color_saturation)
            in_spike = false
        end
    end
    if in_spike
        spike_x = spike_start:n
        spike_y = trace[spike_start:n]
        band!(ax, collect(spike_x), fill(1.0, length(spike_x)), spike_y,
              color=color_saturation)
    end

    # Draw trace line
    lines!(ax, steps, trace, color=color_line, linewidth=0.5)

    # Legend
    elem_reduction = [LineElement(color=color_reduction, linewidth=2)]
    elem_branching = [PolyElement(color=color_saturation)]
    Legend(fig[2, 1],
        [elem_branching, elem_reduction],
        [L"\gamma>1\ \text{ branching}", L"\gamma=1\ \text{ reduction}"],
        orientation = :horizontal,
        halign = :center, valign = :bottom,
        framevisible = false,
        labelsize = 7,
        padding = (2, 2, 2, 2),
        margin = (0, 0, 0, 0),
        patchsize = (14, 8)
    )
    rowgap!(fig.layout, 2)

    # Save figure
    if format == :pdf
        save("$(output_path).pdf", fig, pt_per_unit=1)
        println("Saved: $(output_path).pdf")
    elseif format == :png
        save("$(output_path).png", fig, px_per_unit=4)
        println("Saved: $(output_path).png")
    else
        save("$(output_path).pdf", fig, pt_per_unit=1)
        save("$(output_path).png", fig, px_per_unit=4)
        println("Saved: $(output_path).pdf and $(output_path).png")
    end

    return fig
end

"""
    plot_single_landscape(trace, N; output_path="gamma_single", title="")

Plot a single γ-landscape trace.
"""
function plot_single_landscape(
    trace::Vector{Float64},
    N::Int;
    output_path::String="gamma_single",
    title::String=""
)
    # Single column IJCAI width
    width_pt = 3.25 * 72
    height_pt = 2.1 * 72

    fig = Figure(
        size = (width_pt, height_pt),
        fontsize = 9,
        font = "Times New Roman",
        figure_padding = (4, 4, 4, 4)
    )

    n = length(trace)
    steps = 1:n

    ax = Axis(fig[1, 1],
        xlabel = "Decision step",
        ylabel = L"\gamma",
        title = isempty(title) ? "" : title,
        titlesize = 9,
        xlabelsize = 9,
        ylabelsize = 10,
        xticklabelsize = 8,
        yticklabelsize = 8,
        yticklabelrotation = pi/2,
    )

    # Adaptive y-axis: use actual max + small margin
    max_gamma = maximum(trace)
    y_upper = max_gamma + 0.05
    ylims!(ax, 0.995, y_upper)
    xlims!(ax, 0, n + 1)

    # Colors
    color_reduction = (:steelblue, 0.9)
    color_saturation = (:firebrick, 0.8)

    # Baseline at γ=1
    hlines!(ax, [1.0], color=color_reduction, linewidth=2)

    # Highlight saturation spikes
    for j in 1:n
        if trace[j] > 1.0
            band!(ax, [j-0.5, j+0.5], [1.0, 1.0], [trace[j], trace[j]],
                  color=color_saturation)
        end
    end

    # Trace line
    lines!(ax, steps, trace, color=(:black, 0.5), linewidth=0.4)

    # Legend
    elem_reduction = [LineElement(color=color_reduction, linewidth=2)]
    elem_branching = [PolyElement(color=color_saturation)]
    Legend(fig[2, 1],
        [elem_branching, elem_reduction],
        [L"\gamma>1\ \text{ branching}", L"\gamma=1\ \text{ reduction}"],
        orientation = :horizontal,
        halign = :center, valign = :bottom,
        framevisible = false,
        labelsize = 7,
        padding = (2, 2, 2, 2),
        margin = (0, 0, 0, 0),
        patchsize = (12, 8)
    )
    rowgap!(fig.layout, 2)

    save("$(output_path).pdf", fig, pt_per_unit=1)
    save("$(output_path).png", fig, px_per_unit=4)
    println("Saved: $(output_path).pdf and $(output_path).png")

    return fig
end

"""
    collect_gamma_data(; example_size=14, sizes=[10,12,14], n_instances=5, output_path="results/gamma_data.csv")

Collect γ-landscape data and save to CSV. Separates data collection from plotting.
"""
function collect_gamma_data(;
    example_size::Int=14,
    sizes::Vector{Int}=[10, 12, 14],
    n_instances::Int=5,
    output_path::String="results/gamma_data.csv"
)
    println("Collecting γ-landscape data...")

    # Get one example trace
    data_file = joinpath(@__DIR__, "../benchmarks/data/factoring/numbers_$(example_size)x$(example_size).txt")
    instances = load_instances(data_file; max_instances=1)
    trace, _ = run_gamma_trace(instances[1].n, instances[1].m, instances[1].N)
    println("  Example trace: $(length(trace)) steps, max γ = $(maximum(trace))")

    # Collect ratio data for each size
    println("Computing γ=1 ratios across problem sizes...")
    ratios = Dict{Int, Float64}()
    for sz in sizes
        data_file = joinpath(@__DIR__, "../benchmarks/data/factoring/numbers_$(sz)x$(sz).txt")
        insts = load_instances(data_file; max_instances=n_instances)

        all_gamma = Float64[]
        for inst in insts
            tr, _ = run_gamma_trace(inst.n, inst.m, inst.N)
            append!(all_gamma, tr)
        end

        ratio = count(g -> g == 1.0, all_gamma) / length(all_gamma)
        ratios[sz] = ratio
        @printf("  %dx%d: γ=1 ratio = %.2f%% (%d instances)\n", sz, sz, ratio * 100, n_instances)
    end

    # Save to CSV
    outdir = dirname(output_path)
    !isempty(outdir) && mkpath(outdir)

    # Save trace
    trace_path = replace(output_path, ".csv" => "_trace.csv")
    trace_df = DataFrame(step=1:length(trace), gamma=trace)
    CSV.write(trace_path, trace_df)

    # Save ratios
    ratio_df = DataFrame(size=sizes, ratio=[ratios[sz] for sz in sizes])
    CSV.write(output_path, ratio_df)

    println("\nData saved to:")
    println("  Trace: $(trace_path)")
    println("  Ratios: $(output_path)")

    return (trace=trace, ratios=ratios, sizes=sizes)
end

"""
    load_gamma_data(; data_path="results/gamma_data.csv")

Load previously collected γ-landscape data.
"""
function load_gamma_data(; data_path::String="results/gamma_data.csv")
    trace_path = replace(data_path, ".csv" => "_trace.csv")

    trace_df = CSV.read(trace_path, DataFrame)
    ratio_df = CSV.read(data_path, DataFrame)

    trace = trace_df.gamma
    sizes = ratio_df.size
    ratios = Dict(sz => r for (sz, r) in zip(ratio_df.size, ratio_df.ratio))

    return (trace=trace, ratios=ratios, sizes=sizes)
end

"""
    plot_gamma_landscape_paper(data; output_path="fig_gamma_landscape")

Plot a single γ-landscape from pre-collected data (no inset).
"""
function plot_gamma_landscape_paper(
    data::NamedTuple;
    output_path::String="plots/fig_gamma_landscape"
)
    trace = data.trace
    n = length(trace)
    max_gamma = maximum(trace)

    # Colors
    color_r = :steelblue
    color_s = :firebrick

    # Figure: single panel
    fig = Figure(size = (234, 200), fontsize = 9, font = "Times New Roman",
                 figure_padding = (4, 4, 4, 4))

    ax = Axis(fig[1, 1],
        xlabel = "Decision step",
        ylabel = L"\gamma",
        xlabelsize = 10,
        ylabelsize = 11,
        xticklabelsize = 9,
        yticklabelsize = 9,
        yticklabelrotation = pi/2,
        yticks = [1.0, 1.05, 1.10, 1.15],
    )

    ylims!(ax, 0.995, max(max_gamma + 0.02, 1.15))
    xlims!(ax, 0, n + 1)

    # Draw γ=1 baseline as continuous line
    hlines!(ax, [1.0], color=(color_r, 0.8), linewidth=2)

    # Highlight γ>1 spikes with visible markers
    spike_x = Int[]
    spike_y = Float64[]
    for j in 1:n
        if trace[j] > 1.0
            push!(spike_x, j)
            push!(spike_y, trace[j])
        end
    end

    # Draw spikes as stems (vertical lines from 1 to gamma)
    for (x, y) in zip(spike_x, spike_y)
        lines!(ax, [x, x], [1.0, y], color=(color_s, 0.9), linewidth=2)
    end
    # Add markers at spike tops
    scatter!(ax, spike_x, spike_y, color=color_s, markersize=5, marker=:circle)

    # Legend
    elem_reduction = [LineElement(color=(color_r, 0.8), linewidth=2)]
    elem_branching = [MarkerElement(color=color_s, marker=:circle, markersize=7)]
    Legend(fig[2, 1],
        [elem_branching, elem_reduction],
        [L"\gamma>1\ \text{ branching}", L"\gamma=1\ \text{ reduction}"],
        orientation = :horizontal,
        halign = :center, valign = :bottom,
        framevisible = false,
        labelsize = 9,
        padding = (2, 2, 2, 2),
        margin = (0, 0, 0, 0),
        patchsize = (16, 10)
    )
    rowgap!(fig.layout, 2)

    # Ensure output directory exists
    outdir = dirname(output_path)
    !isempty(outdir) && mkpath(outdir)

    save("$(output_path).pdf", fig, pt_per_unit=1)
    save("$(output_path).png", fig, px_per_unit=4)
    println("Saved: $(output_path).pdf and $(output_path).png")

    return fig
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    # Step 1: Collect data (slow, run once)
    data = collect_gamma_data(
        example_size=14,
        sizes=[10, 12, 14],
        n_instances=5,
        output_path="results/gamma_data.csv"
    )

    # Step 2: Plot (fast, can iterate)
    plot_gamma_landscape_paper(data, output_path="results/fig_gamma_landscape")
end
