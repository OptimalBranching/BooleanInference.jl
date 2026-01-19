"""
Experiment 1 Utilities: Infrastructure for OB Framework Design Choices experiments
"""

using BooleanInference
using OptimalBranchingCore
using DataFrames
using CSV
using JSON3
using Statistics
using Printf
using Dates

# ============================================================================
# System Information
# ============================================================================

"""
    get_system_info()

Collect system information for reproducibility.
"""
function get_system_info()
    return Dict{String,Any}(
        "julia_version" => string(VERSION),
        "os" => string(Sys.KERNEL),
        "machine" => Sys.MACHINE,
        "cpu_threads" => Sys.CPU_THREADS,
        "total_memory_gb" => round(Sys.total_memory() / 2^30, digits=2),
        "word_size" => Sys.WORD_SIZE,
        "hostname" => gethostname()
    )
end

"""
    get_experiment_metadata(experiment_name::String; description::String="")

Create metadata for an experiment run.
"""
function get_experiment_metadata(experiment_name::String; description::String="")
    ts = now()
    return Dict{String,Any}(
        "experiment_name" => experiment_name,
        "description" => description,
        "timestamp" => Dates.format(ts, "yyyy-mm-dd HH:MM:SS"),
        "timestamp_utc" => Dates.format(now(UTC), "yyyy-mm-dd HH:MM:SS"),
        "timestamp_compact" => Dates.format(ts, "yyyymmdd_HHMMSS"),
        "system_info" => get_system_info()
    )
end

"""
    get_output_path(output_dir::String, experiment_name::String; use_timestamp::Bool=true)

Generate output file path with optional timestamp to avoid overwriting.
"""
function get_output_path(output_dir::String, experiment_name::String; use_timestamp::Bool=true)
    mkpath(output_dir)
    if use_timestamp
        ts = Dates.format(now(), "yyyymmdd_HHMMSS")
        return joinpath(output_dir, "$(experiment_name)_$(ts)")
    else
        return joinpath(output_dir, experiment_name)
    end
end

"""
    ExperimentResult

Stores results for a single solver run
"""
struct ExperimentResult
    instance_name::String
    n::Int
    m::Int
    N::Int
    config_name::String
    found::Bool
    solve_time::Float64
    branching_nodes::Int         # Number of branching nodes (k≥2 children)
    children_explored::Int       # Total children explored (search tree size)
    unsat_leaves::Int           # UNSAT terminal nodes (conflicts/dead-ends)
    reduction_nodes::Int        # Number of reduction nodes (γ=1)
    avg_gamma::Float64          # Average branching factor
    # Additional fields
    extra_data::Dict{String,Any}
end

"""
    load_factoring_instances(file_path::String; max_instances::Int=10)

Load factoring instances from a text file.
Returns a vector of tuples (n, m, N, p, q, name)
"""
function load_factoring_instances(file_path::String; max_instances::Int=10)
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
    run_single_experiment(n, m, N, bsconfig, reducer; timeout=300.0, show_stats=false)

Run a single factoring instance with given configuration.
Returns ExperimentResult or nothing if timeout/error.
"""
function run_single_experiment(
    n::Int,
    m::Int,
    N::Int,
    config_name::String,
    bsconfig::BranchingStrategy,
    reducer::AbstractReducer;
    timeout::Float64=300.0,
    show_stats::Bool=false
)
    instance_name = "$(n)x$(m)_$(N)"

    try
        # Time the solve
        start_time = time()
        a, b, stats = solve_factoring(
            n, m, N;
            bsconfig=bsconfig,
            reducer=reducer,
            show_stats=show_stats,
            cdcl_cutoff=1.0
        )
        elapsed = time() - start_time

        # Check if correct
        found = (a * b == N)

        # Get average gamma from stats (only at branching nodes)
        avg_gamma = stats.avg_gamma

        # Compute additional metrics
        total_nodes = stats.total_nodes
        reduction_ratio = total_nodes > 0 ? stats.reduction_nodes / total_nodes : 0.0
        # Effective gamma = average children per node (including all node types)
        effective_gamma = total_nodes > 0 ? stats.children_explored / total_nodes : 1.0

        return ExperimentResult(
            instance_name,
            n, m, N,
            config_name,
            found,
            elapsed,
            stats.branching_nodes,
            stats.children_explored,
            stats.unsat_leaves,
            stats.reduction_nodes,
            avg_gamma,
            Dict{String,Any}(
                "reduction_ratio" => reduction_ratio,
                "effective_gamma" => effective_gamma,
                "total_nodes" => total_nodes,
                "sat_leaves" => stats.sat_leaves,
                "terminal_nodes" => stats.terminal_nodes,
                "children_generated" => stats.children_generated,
                "avg_table_configs" => stats.avg_table_configs,
                "avg_table_vars" => stats.avg_table_vars,
                "max_table_configs" => stats.max_table_configs
            )
        )
    catch e
        @warn "Error running experiment" instance=instance_name config=config_name exception=e
        return nothing
    end
end

"""
    results_to_dataframe(results::Vector{ExperimentResult})

Convert results to a DataFrame for analysis
"""
function results_to_dataframe(results::Vector{ExperimentResult})
    return DataFrame([
        (
            instance=r.instance_name,
            n=r.n,
            m=r.m,
            N=r.N,
            config=r.config_name,
            found=r.found,
            time=r.solve_time,
            total_nodes=Base.get(r.extra_data, "total_nodes", 0),
            branching_nodes=r.branching_nodes,
            reduction_nodes=r.reduction_nodes,
            terminal_nodes=Base.get(r.extra_data, "terminal_nodes", 0),
            children_generated=Base.get(r.extra_data, "children_generated", 0),
            unsat_leaves=r.unsat_leaves,
            avg_gamma=r.avg_gamma
        )
        for r in results
    ])
end

"""
    save_results(results::Vector{ExperimentResult}, filepath::String; metadata::Dict=Dict())

Save results to CSV and JSON with metadata.
"""
function save_results(results::Vector{ExperimentResult}, filepath::String;
                      metadata::Dict{String,Any}=Dict{String,Any}())
    # Save as CSV (flat format for easy analysis)
    df = results_to_dataframe(results)
    CSV.write(filepath * ".csv", df)

    # Save as JSON with full data and metadata
    results_data = [
        Dict{String,Any}(
            "instance" => r.instance_name,
            "n" => r.n,
            "m" => r.m,
            "N" => r.N,
            "config" => r.config_name,
            "found" => r.found,
            "solve_time" => r.solve_time,
            "total_nodes" => Base.get(r.extra_data, "total_nodes", 0),
            "branching_nodes" => r.branching_nodes,
            "reduction_nodes" => r.reduction_nodes,
            "terminal_nodes" => Base.get(r.extra_data, "terminal_nodes", 0),
            "children_explored" => r.children_explored,
            "unsat_leaves" => r.unsat_leaves,
            "avg_gamma" => r.avg_gamma,
            "extra" => r.extra_data
        )
        for r in results
    ]

    # Complete JSON with metadata
    json_output = Dict{String,Any}(
        "metadata" => isempty(metadata) ? get_experiment_metadata("unknown") : metadata,
        "results" => results_data,
        "summary" => Dict{String,Any}(
            "total_instances" => length(results),
            "configs" => unique(r.config_name for r in results),
            "bit_sizes" => sort(unique(r.n * 2 for r in results))
        )
    )

    open(filepath * ".json", "w") do f
        JSON3.pretty(f, json_output)
    end

    println("Results saved to:")
    println("  - $(filepath).csv")
    println("  - $(filepath).json")
end

"""
    save_knuth_results(knuth_results::Dict, filepath::String; metadata::Dict=Dict())

Save Knuth estimator analysis results.
"""
function save_knuth_results(knuth_results::Dict, filepath::String;
                            metadata::Dict{String,Any}=Dict{String,Any}())
    # Convert Knuth results to serializable format
    knuth_data = Dict{String,Any}()
    for (key, results) in knuth_results
        knuth_data[key] = Dict{String,Any}()
        for (measure_name, res) in results
            knuth_data[key][measure_name] = Dict{String,Any}(
                "uniform" => Dict{String,Any}(
                    "log10_mean_size" => res.uniform.log10_mean_size,
                    "log_variance" => res.uniform.log_variance,
                    "num_samples" => res.uniform.num_samples,
                    "avg_path_length" => res.uniform.avg_path_length,
                    "avg_gamma" => res.uniform.avg_gamma
                ),
                "importance" => Dict{String,Any}(
                    "log10_mean_size" => res.importance.log10_mean_size,
                    "log_variance" => res.importance.log_variance,
                    "num_samples" => res.importance.num_samples,
                    "avg_path_length" => res.importance.avg_path_length,
                    "avg_gamma" => res.importance.avg_gamma
                ),
                "variance_ratio" => res.importance.log_variance / max(res.uniform.log_variance, 1e-10)
            )
        end
    end

    json_output = Dict{String,Any}(
        "metadata" => isempty(metadata) ? get_experiment_metadata("knuth_analysis") : metadata,
        "knuth_analysis" => knuth_data
    )

    open(filepath * "_knuth.json", "w") do f
        JSON3.pretty(f, json_output)
    end

    println("Knuth results saved to: $(filepath)_knuth.json")
end

"""
    load_results(filepath::String)

Load results from JSON file
"""
function load_results(filepath::String)
    json_path = endswith(filepath, ".json") ? filepath : filepath * ".json"
    data = JSON3.read(read(json_path, String))

    return [
        ExperimentResult(
            d["instance"],
            d["n"],
            d["m"],
            d["N"],
            d["config"],
            d["found"],
            d["solve_time"],
            d["branching_nodes"],
            Base.get(d, "children_explored", 0),  # Backward compatibility
            d["unsat_leaves"],
            d["reduction_nodes"],
            d["avg_gamma"],
            # JSON3 may materialize object keys as Symbols; normalize to Dict{String,Any}
            begin
                extra = Dict{String,Any}(String(k) => v for (k, v) in pairs(Base.get(d, "extra", Dict())))
                # Ensure total_nodes and terminal_nodes are in extra_data for backward compatibility
                if !haskey(extra, "total_nodes") && haskey(d, "total_nodes")
                    extra["total_nodes"] = d["total_nodes"]
                end
                if !haskey(extra, "terminal_nodes") && haskey(d, "terminal_nodes")
                    extra["terminal_nodes"] = d["terminal_nodes"]
                end
                extra
            end
        )
        for d in data
    ]
end

"""
    print_summary_table(results::Vector{ExperimentResult}; groupby=:config)

Print a summary table of results (simplified for paper)
"""
function print_summary_table(results::Vector{ExperimentResult}; groupby::Symbol=:config)
    df = results_to_dataframe(results)

    if groupby == :config
        # First aggregate for each config
        grouped = combine(DataFrames.groupby(df, :config),
            :time => median => :median_time,
            :terminal_nodes => median => :median_leaves,
            :children_generated => sum => :total_children_generated,
            :branching_nodes => sum => :total_branching_nodes,
            :reduction_nodes => sum => :total_reduction_nodes,
            nrow => :n
        )

        # Calculate Mean Branch Factor gamma after aggregation
        # gamma = (children_generated+reduction_nodes)/(branching_nodes+reduction_nodes)
        # For DPLL, default to 2.0
        grouped[!, :mean_gamma] = [
            if r.config == "DPLL"
                2.0
            else
                denom = r.total_branching_nodes + r.total_reduction_nodes
                denom > 0 ? (r.total_children_generated + r.total_reduction_nodes) / denom : 0.0
            end
            for r in eachrow(grouped)
        ]

        # Select only the columns we want to display
        grouped = select(grouped, :config, :median_time, :median_leaves, :mean_gamma, :n)

        println("\n" * "="^80)
        println("Summary by Configuration")
        println("="^80)
        println(grouped)
        println("="^80)
    end
end

# Helper function to get stats dict
function get(stats, key::Symbol, default)
    if hasfield(typeof(stats), key)
        return getfield(stats, key)
    else
        return default
    end
end

