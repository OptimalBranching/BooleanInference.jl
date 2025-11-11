# Detailed statistics (optional, only allocated when needed)
mutable struct DetailedStats
    # Depth distribution (node count per depth)
    depth_distribution::Vector{Int}

    # Branching factor history (actual child count per branch)
    branching_factors::Vector{Int}

    # Propagation efficiency
    propagation_calls::Int
    domain_reductions::Int
    early_unsat_detections::Int

    # Time breakdown (seconds)
    time_propagation::Float64
    time_branching::Float64
    time_contraction::Float64
    time_filtering::Float64

    # Cache efficiency
    cache_hits::Int
    cache_misses::Int

    # Branch decision quality
    variable_selection_counts::Dict{Int, Int}
    remaining_vars_at_branch::Vector{Int}
    depth_at_selection::Vector{Int}  # Depth when each variable was selected
    variable_selection_sequence::Vector{Int}  # Variable selection order (by pick sequence)
    successful_paths::Vector{Vector{Int}}  # Successful paths from root to solution (variable sequence)
end

DetailedStats() = DetailedStats(
    Int[],
    Int[],
    0, 0, 0,
    0.0, 0.0, 0.0, 0.0,
    0, 0,
    Dict{Int, Int}(),
    Int[],
    Int[],
    Int[],
    Vector{Int}[]
)

mutable struct BranchingStats
    total_branches::Int
    total_subproblems::Int
    max_depth::Int
    solved_leaves::Int

    detailed::Union{Nothing, DetailedStats}
end

BranchingStats(verbose::Bool = false) = BranchingStats(
    0, 0, 0, 0,
    verbose ? DetailedStats() : nothing
)

function reset!(stats::BranchingStats)
    stats.total_branches = 0
    stats.total_subproblems = 0
    stats.max_depth = 0
    stats.solved_leaves = 0

    if !isnothing(stats.detailed)
        d = stats.detailed
        empty!(d.depth_distribution)
        empty!(d.branching_factors)
        d.propagation_calls = 0
        d.domain_reductions = 0
        d.early_unsat_detections = 0
        d.time_propagation = 0.0
        d.time_branching = 0.0
        d.time_contraction = 0.0
        d.time_filtering = 0.0
        d.cache_hits = 0
        d.cache_misses = 0
        empty!(d.variable_selection_counts)
        empty!(d.remaining_vars_at_branch)
        empty!(d.depth_at_selection)
        empty!(d.variable_selection_sequence)
        empty!(d.successful_paths)
    end

    return stats
end

function Base.copy(stats::BranchingStats)
    detailed_copy = if stats.detailed !== nothing
        d = stats.detailed
        DetailedStats(
            copy(d.depth_distribution),
            copy(d.branching_factors),
            d.propagation_calls,
            d.domain_reductions,
            d.early_unsat_detections,
            d.time_propagation,
            d.time_branching,
            d.time_contraction,
            d.time_filtering,
            d.cache_hits,
            d.cache_misses,
            copy(d.variable_selection_counts),
            copy(d.remaining_vars_at_branch),
            copy(d.depth_at_selection),
            copy(d.variable_selection_sequence),
            [copy(path) for path in d.successful_paths]
        )
    else
        nothing
    end

    return BranchingStats(
        stats.total_branches,
        stats.total_subproblems,
        stats.max_depth,
        stats.solved_leaves,
        detailed_copy
    )
end

function Base.getproperty(stats::BranchingStats, name::Symbol)
    if name === :avg_branching_factor
        return stats.total_branches > 0 ?
            stats.total_subproblems / stats.total_branches :
            0.0
    else
        return getfield(stats, name)
    end
end

function Base.propertynames(::BranchingStats; private::Bool=false)
    return (fieldnames(BranchingStats)..., :avg_branching_factor)
end

@inline function record_depth!(stats::BranchingStats, depth::Int)
    depth > stats.max_depth && (stats.max_depth = depth)
    return nothing
end

@inline function record_branch!(stats::BranchingStats, subproblem_count::Int, depth::Int)
    stats.total_branches += 1
    stats.total_subproblems += subproblem_count
    record_depth!(stats, depth)

    # Record detailed statistics
    if stats.detailed !== nothing
        d = stats.detailed
        push!(d.branching_factors, subproblem_count)

        # Update the depth distribution
        while length(d.depth_distribution) <= depth
            push!(d.depth_distribution, 0)
        end
        d.depth_distribution[depth + 1] += 1
    end

    return nothing
end

@inline function record_unsat_leaf!(stats::BranchingStats, depth::Int)
    record_depth!(stats, depth)
    return nothing
end

@inline function record_solved_leaf!(stats::BranchingStats, depth::Int)
    stats.solved_leaves += 1
    record_depth!(stats, depth)
    return nothing
end

@inline function record_skipped_subproblem!(stats::BranchingStats)
    return nothing
end

# === Detailed statistics recording functions ===

@inline function record_propagation!(stats::BranchingStats, time_elapsed::Float64 = 0.0)
    if stats.detailed !== nothing
        stats.detailed.propagation_calls += 1
        stats.detailed.time_propagation += time_elapsed
    end
    return nothing
end

@inline function record_domain_reduction!(stats::BranchingStats, reduction_count::Int)
    if stats.detailed !== nothing
        stats.detailed.domain_reductions += reduction_count
    end
    return nothing
end

@inline function record_early_unsat!(stats::BranchingStats)
    if stats.detailed !== nothing
        stats.detailed.early_unsat_detections += 1
    end
    return nothing
end

@inline function record_branching_time!(stats::BranchingStats, time_elapsed::Float64)
    if stats.detailed !== nothing
        stats.detailed.time_branching += time_elapsed
    end
    return nothing
end

@inline function record_contraction_time!(stats::BranchingStats, time_elapsed::Float64)
    if stats.detailed !== nothing
        stats.detailed.time_contraction += time_elapsed
    end
    return nothing
end

@inline function record_filtering_time!(stats::BranchingStats, time_elapsed::Float64)
    if stats.detailed !== nothing
        stats.detailed.time_filtering += time_elapsed
    end
    return nothing
end

@inline function record_cache_hit!(stats::BranchingStats)
    if stats.detailed !== nothing
        stats.detailed.cache_hits += 1
    end
    return nothing
end

@inline function record_cache_miss!(stats::BranchingStats)
    if stats.detailed !== nothing
        stats.detailed.cache_misses += 1
    end
    return nothing
end

@inline function record_variable_selection!(stats::BranchingStats, var::Int, remaining_vars::Int, depth::Int)
    if stats.detailed !== nothing
        d = stats.detailed
        d.variable_selection_counts[var] = get(d.variable_selection_counts, var, 0) + 1
        push!(d.remaining_vars_at_branch, remaining_vars)
        push!(d.depth_at_selection, depth)
        push!(d.variable_selection_sequence, var)
    end
    return nothing
end

# Check if we need to track paths (only when detailed stats are enabled)
@inline needs_path_tracking(stats::BranchingStats) = !isnothing(stats.detailed)

# === Statistics analysis and visualization ===
function print_stats_summary(stats::BranchingStats; io::IO = stdout)
    println(io, "=== Branching Statistics ===")
    println(io, "Branch decisions: ", stats.total_branches)
    println(io, "Child nodes: ", stats.total_subproblems)
    println(io, "Max depth: ", stats.max_depth + 1)
    println(io, "Solved leaves: ", stats.solved_leaves)

    if stats.detailed !== nothing
        println(io, "\n=== Detailed Statistics ===")
        d = stats.detailed

        # Propagation statistics
        println(io, "\nPropagation:")
        println(io, "  Calls: ", d.propagation_calls)
        println(io, "  Domain reductions: ", d.domain_reductions)
        println(io, "  Early UNSAT detections: ", d.early_unsat_detections)
        if d.propagation_calls > 0
            println(io, "  Avg domains reduced per call: ",
                    round(d.domain_reductions / d.propagation_calls, digits=2))
        end

        # Timing statistics
        total_time = d.time_propagation + d.time_branching + d.time_contraction + d.time_filtering
        println(io, "\nTime breakdown:")
        if total_time > 0
            println(io, "  Propagation: ", round(d.time_propagation, digits=5), "s (",
                    round(100 * d.time_propagation / total_time, digits=5), "%)")
            println(io, "  Branching: ", round(d.time_branching, digits=5), "s (",
                    round(100 * d.time_branching / total_time, digits=5), "%)")
            println(io, "  Contraction: ", round(d.time_contraction, digits=5), "s (",
                    round(100 * d.time_contraction / total_time, digits=5), "%)")
            println(io, "  Filtering: ", round(d.time_filtering, digits=5), "s (",
                    round(100 * d.time_filtering / total_time, digits=5), "%)")
            println(io, "  Total: ", round(total_time, digits=5), "s")
        else
            println(io, "  (Time statistics not recorded)")
        end

        # Cache statistics
        cache_total = d.cache_hits + d.cache_misses
        if cache_total > 0
            println(io, "\nCache efficiency:")
            println(io, "  Hits: ", d.cache_hits)
            println(io, "  Misses: ", d.cache_misses)
            println(io, "  Hit rate: ",
                    round(100 * d.cache_hits / cache_total, digits=1), "%")
        end

        # Branching factor distribution
        if !isempty(d.branching_factors)
            println(io, "\nBranching factor distribution:")
            println(io, "  Min: ", minimum(d.branching_factors))
            println(io, "  Max: ", maximum(d.branching_factors))
            println(io, "  Mean: ", round(sum(d.branching_factors) / length(d.branching_factors), digits=2))
            println(io, "  Median: ", median(d.branching_factors))
        end

        # Depth distribution
        if !isempty(d.depth_distribution)
            println(io, "\nDepth distribution:")
            # Compute cumulative node counts per depth to align with branching_factors
            cumulative_nodes = 0
            for (depth_idx, node_count) in enumerate(d.depth_distribution)
                if node_count > 0
                    depth = depth_idx  # Display depth starting from 1
                    # Branching factor indices at this depth: cumulative_nodes+1 to cumulative_nodes+node_count
                    start_idx = cumulative_nodes + 1
                    end_idx = cumulative_nodes + node_count
                    
                    if start_idx <= length(d.branching_factors)
                        end_idx = min(end_idx, length(d.branching_factors))
                        depth_branching_factors = d.branching_factors[start_idx:end_idx]
                        avg_bf = round(sum(depth_branching_factors) / length(depth_branching_factors), digits=2)
                        total_subproblems = sum(depth_branching_factors)
                        println(io, "  Depth ", depth, ": ", node_count, " nodes, ", 
                                total_subproblems, " subproblems, avg branching factor: ", avg_bf)
                    else
                        println(io, "  Depth ", depth, ": ", node_count, " nodes")
                    end
                    cumulative_nodes += node_count
                end
            end
        end

        # Variable selection statistics
        if !isempty(d.variable_selection_counts)
            println(io, "\nVariable selection (top 10):")
            sorted_vars = sort(collect(d.variable_selection_counts), by=x->x[2], rev=true)
            # Compute the average remaining variable count and depth per variable
            if !isempty(d.variable_selection_sequence) && 
               length(d.variable_selection_sequence) == length(d.remaining_vars_at_branch) &&
               length(d.variable_selection_sequence) == length(d.depth_at_selection)
                for (var, count) in sorted_vars[1:min(10, length(sorted_vars))]
                    # Locate every position where this variable was selected
                    var_indices = [i for (i, v) in enumerate(d.variable_selection_sequence) if v == var]
                    avg_remaining = round(sum(d.remaining_vars_at_branch[i] for i in var_indices) / length(var_indices), digits=1)
                    avg_depth = round(sum(d.depth_at_selection[i] for i in var_indices) / length(var_indices), digits=1)
                    println(io, "  Var ", var, ": ", count, " times, ",
                            "avg remaining vars: ", avg_remaining, ", ",
                            "avg depth: ", avg_depth + 1)
                end
            else
                # Fallback display: show selection counts only
                for (var, count) in sorted_vars[1:min(10, length(sorted_vars))]
                    println(io, "  Var ", var, ": ", count, " times")
                end
            end
        end

        if !isempty(d.successful_paths)
            println(io, "\nSuccessful paths:")
            for (path_idx, path) in enumerate(d.successful_paths)
                println(io, "  Path ", path_idx, ": ", join([string(v) for v in path], " -> "))
            end
        end
    end
end
