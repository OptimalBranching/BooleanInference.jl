"""
Experiment 1.1: Branching Rule Quality

Compare different branching rules with FIXED variable selection order:
- DPLL: Single-variable 0/1 branching (γ=2.0)
- NaiveBranch: Multi-variable branching from branch table, no optimization
- GreedyMerge: Near-optimal branching rule (optimizes γ via set cover)

Fixed parameters:
- selector = MinGammaSelector(3, 4, 0) for NaiveBranch/GreedyMerge
- measure = NumUnfixedTensors()

This isolates the branching rule quality by keeping variable selection consistent.
"""

include("exp1_utils.jl")

using BooleanInference


"""
    TimeoutResult

Result when experiment times out or fails.
"""
struct TimeoutResult
    instance_name::String
    n::Int
    m::Int
    N::Int
    config_name::String
    status::Symbol  # :timeout, :oom, :error
end

function run_exp1_1(;
    max_instances::Int=10,
    output_dir::String="results",
    bit_sizes::Vector{Int}=[10, 12],
    timeout::Float64=100.0
)
    println("\n" * "="^80)
    println("Experiment 1.1: Branching Rule Quality Comparison")
    println("="^80)

    # Create experiment metadata
    metadata = get_experiment_metadata(
        "exp1_1_branching_rules",
        description="Compare DPLL, NaiveBranch, and GreedyMerge branching rules on factoring instances."
    )
    metadata["parameters"] = Dict{String,Any}(
        "bit_sizes" => bit_sizes,
        "max_instances" => max_instances,
        "timeout" => timeout
    )

    data_dir = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring")
    reducer = NoReducer()
    k = 3
    max_tensors = 4

    # Results storage
    all_results = ExperimentResult[]
    timeout_results = TimeoutResult[]

    for bit_size in bit_sizes
        data_file = joinpath(data_dir, "numbers_$(bit_size)x$(bit_size).txt")
        if !isfile(data_file)
            @warn "Data file not found: $data_file"
            continue
        end

        instances = load_factoring_instances(data_file; max_instances=max_instances)
        println("\n[$(bit_size)x$(bit_size)] Loaded $(length(instances)) instances")

        # Warm-up on first bit size
        if bit_size == bit_sizes[1] && !isempty(instances)
            println("Warming up...")
            warmup_inst = instances[1]
            try
                solve_factoring(warmup_inst.n, warmup_inst.m, warmup_inst.N;
                    bsconfig=BranchingStrategy(
                        table_solver=TNContractionSolver(),
                        selector=MinGammaSelector(k, max_tensors, 0),
                        measure=NumUnfixedTensors(),
                        set_cover_solver=GreedyMerge()
                    ),
                    reducer=reducer,
                    show_stats=false,
                    cdcl_cutoff=1.0
                )
                println("Warm-up completed")
            catch e
                @warn "Warm-up failed" exception=e
            end
        end

        # Define configurations
        configs = [
            (
                name="DPLL",
                bsconfig=BranchingStrategy(
                    table_solver=TNContractionSolver(),
                    selector=DPLLSelector(),
                    measure=NumUnfixedVars(),
                    set_cover_solver=NaiveBranch()
                ),
                reducer=NoReducer()
            ),
            (
                name="NaiveBranch",
                bsconfig=BranchingStrategy(
                    table_solver=TNContractionSolver(),
                    selector=MinGammaSelector(k, max_tensors, 0),
                    measure=NumUnfixedTensors(),
                    set_cover_solver=NaiveBranch()
                ),
                reducer=reducer
            ),
            (
                name="GreedyMerge",
                bsconfig=BranchingStrategy(
                    table_solver=TNContractionSolver(),
                    selector=MinGammaSelector(k, max_tensors, 0),
                    measure=NumUnfixedTensors(),
                    set_cover_solver=GreedyMerge()
                ),
                reducer=reducer
            )
        ]

        for (idx, inst) in enumerate(instances)
            println("\n  [$(idx)/$(length(instances))] N=$(inst.N)")

            for config in configs
                # Skip DPLL for all (too slow/unpredictable)
                if config.name == "DPLL"
                    print("    - $(config.name)... ")
                    println("⏭ Skipped (too slow)")
                    push!(timeout_results, TimeoutResult(
                        "$(inst.n)x$(inst.m)_$(inst.N)",
                        inst.n, inst.m, inst.N,
                        config.name,
                        :timeout
                    ))
                    continue
                end

                print("    - $(config.name)... ")
                flush(stdout)

                try
                    start_time = time()
                    a, b, stats = solve_factoring(
                        inst.n, inst.m, inst.N;
                        bsconfig=config.bsconfig,
                        reducer=config.reducer,
                        show_stats=false,
                        cdcl_cutoff=1.0
                    )
                    elapsed = time() - start_time
                    found = !isnothing(a) && !isnothing(b) && a * b == inst.N

                    # Check timeout (record as timeout if exceeded, but still save result)
                    if elapsed > timeout
                        push!(timeout_results, TimeoutResult(
                            "$(inst.n)x$(inst.m)_$(inst.N)",
                            inst.n, inst.m, inst.N,
                            config.name,
                            :timeout
                        ))
                        @printf("⏱ %.2fs (>%.0fs), %d leaves\n", elapsed, timeout, stats.terminal_nodes)
                    else
                        result = ExperimentResult(
                            "$(inst.n)x$(inst.m)_$(inst.N)",
                            inst.n, inst.m, inst.N,
                            config.name,
                            found,
                            elapsed,
                            stats.branching_nodes,
                            stats.children_explored,
                            stats.unsat_leaves,
                            stats.reduction_nodes,
                            stats.avg_gamma,
                            Dict{String,Any}(
                                "total_nodes" => stats.total_nodes,
                                "terminal_nodes" => stats.terminal_nodes,
                                "sat_leaves" => stats.sat_leaves,
                                "children_generated" => stats.children_generated
                            )
                        )
                        push!(all_results, result)
                        @printf("✓ %.2fs, %d leaves, γ=%.3f\n",
                            elapsed, stats.terminal_nodes, stats.avg_gamma)
                    end
                catch e
                    if e isa OutOfMemoryError
                        push!(timeout_results, TimeoutResult(
                            "$(inst.n)x$(inst.m)_$(inst.N)",
                            inst.n, inst.m, inst.N,
                            config.name,
                            :oom
                        ))
                        println("💥 OOM")
                    else
                        push!(timeout_results, TimeoutResult(
                            "$(inst.n)x$(inst.m)_$(inst.N)",
                            inst.n, inst.m, inst.N,
                            config.name,
                            :error
                        ))
                        println("✗ Error: $e")
                    end
                end
            end
        end
    end

    # Save results
    output_path = get_output_path(output_dir, "exp1_1_branching_rules")
    save_results(all_results, output_path; metadata=metadata)

    # Also save timeout results
    if !isempty(timeout_results)
        timeout_df = DataFrame(
            instance = [r.instance_name for r in timeout_results],
            n = [r.n for r in timeout_results],
            m = [r.m for r in timeout_results],
            N = [r.N for r in timeout_results],
            config = [r.config_name for r in timeout_results],
            status = [String(r.status) for r in timeout_results]
        )
        CSV.write(output_path * "_timeouts.csv", timeout_df)
        println("Timeout results saved to: $(output_path)_timeouts.csv")
    end

    # Print summary table for paper
    print_paper_table(all_results, timeout_results, bit_sizes)

    return (results=all_results, timeouts=timeout_results)
end

"""
Print table in paper format.
"""
function print_paper_table(results::Vector{ExperimentResult}, timeouts::Vector{TimeoutResult}, bit_sizes::Vector{Int})
    println("\n" * "="^80)
    println("Paper Table: Branching Rule Comparison")
    println("="^80)

    configs = ["DPLL", "NaiveBranch", "GreedyMerge"]

    println()
    @printf("%-12s %8s %12s %15s %10s\n", "Config", "Bit Len", "Time (s)", "#Leaf Nodes", "Avg γ")
    println("-"^60)

    for bit_size in bit_sizes
        for (i, config) in enumerate(configs)
            # Check if this config timed out
            timeout_entry = findfirst(t -> t.n == bit_size && t.config_name == config, timeouts)

            if timeout_entry !== nothing
                status = timeouts[timeout_entry].status
                status_str = status == :timeout ? "Timeout" : (status == :oom ? "OOM" : "Error")
                if i == 1
                    @printf("%-12s %8d %12s %15s %10s\n", config, bit_size * 2, status_str, "-", "-")
                else
                    @printf("%-12s %8s %12s %15s %10s\n", config, "", status_str, "-", "-")
                end
            else
                # Get results for this config and bit size
                config_results = filter(r -> r.n == bit_size && r.config_name == config, results)

                if !isempty(config_results)
                    median_time = median([r.solve_time for r in config_results])
                    median_leaves = median([Base.get(r.extra_data, "terminal_nodes", 0) for r in config_results])

                    # Compute mean gamma: total_edges / total_non_leaf_nodes
                    if config == "DPLL"
                        mean_gamma = 2.0
                    else
                        total_edges = sum(Base.get(r.extra_data, "children_generated", 0) + r.reduction_nodes for r in config_results)
                        total_non_leaf = sum(r.branching_nodes + r.reduction_nodes for r in config_results)
                        mean_gamma = total_non_leaf > 0 ? total_edges / total_non_leaf : 0.0
                    end

                    if i == 1
                        @printf("%-12s %8d %12.3f %15.0f %10.3f\n",
                            config, bit_size * 2, median_time, median_leaves, mean_gamma)
                    else
                        @printf("%-12s %8s %12.3f %15.0f %10.3f\n",
                            config, "", median_time, median_leaves, mean_gamma)
                    end
                else
                    if i == 1
                        @printf("%-12s %8d %12s %15s %10s\n", config, bit_size * 2, "-", "-", "-")
                    else
                        @printf("%-12s %8s %12s %15s %10s\n", config, "", "-", "-", "-")
                    end
                end
            end
        end
        println("-"^60)
    end

    # Print LaTeX version
    println("\n" * "="^80)
    println("LaTeX Table:")
    println("="^80)
    print_latex_table(results, timeouts, bit_sizes)
end

function print_latex_table(results::Vector{ExperimentResult}, timeouts::Vector{TimeoutResult}, bit_sizes::Vector{Int})
    configs = ["DPLL", "NaiveBranch", "GreedyMerge"]

    println(raw"""
\begin{table}[htbp]
    \centering
    \caption{Comparison of branching strategies under a fixed focus-variable selection.}
    \begin{tabular}{lrrrr}
    \toprule
    Config & \makecell{Bit\\Length} & \makecell{Median\\Time (s)} & \makecell{Median\\Leaves} & \makecell{Mean\\$\gamma$} \\
    \midrule""")

    for (bs_idx, bit_size) in enumerate(bit_sizes)
        for (i, config) in enumerate(configs)
            timeout_entry = findfirst(t -> t.n == bit_size && t.config_name == config, timeouts)

            bit_str = i == 1 ? "\\multirow{3}{*}{$(bit_size * 2)}" : ""

            if timeout_entry !== nothing
                status = timeouts[timeout_entry].status
                status_str = status == :timeout ? "Timeout" : (status == :oom ? "OOM" : "Error")
                println("    $(config) & $(bit_str) & $(status_str) & -- & -- \\\\")
            else
                config_results = filter(r -> r.n == bit_size && r.config_name == config, results)

                if !isempty(config_results)
                    median_time = median([r.solve_time for r in config_results])
                    median_leaves = median([Base.get(r.extra_data, "terminal_nodes", 0) for r in config_results])

                    # Compute mean gamma: total_edges / total_non_leaf_nodes
                    if config == "DPLL"
                        mean_gamma = 2.0
                    else
                        total_edges = sum(Base.get(r.extra_data, "children_generated", 0) + r.reduction_nodes for r in config_results)
                        total_non_leaf = sum(r.branching_nodes + r.reduction_nodes for r in config_results)
                        mean_gamma = total_non_leaf > 0 ? total_edges / total_non_leaf : 0.0
                    end

                    # Format with thousands separator
                    leaves_str = format_number(round(Int, median_leaves))

                    @printf("    %s & %s & %.3f & %s & %.3f \\\\\n",
                        config, bit_str, median_time, leaves_str, mean_gamma)
                else
                    println("    $(config) & $(bit_str) & -- & -- & -- \\\\")
                end
            end
        end

        if bs_idx < length(bit_sizes)
            println("    \\midrule")
        end
    end

    println(raw"""    \bottomrule
    \end{tabular}
    \label{tab:summary_by_config}
\end{table}""")
end

function format_number(n::Int)
    s = string(n)
    parts = String[]
    while length(s) > 3
        push!(parts, s[end-2:end])
        s = s[1:end-3]
    end
    push!(parts, s)
    return join(reverse(parts), "{,}")
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_exp1_1(
        max_instances=10,
        output_dir="results",
        bit_sizes=[10, 12],
        timeout=100.0
    )
end
