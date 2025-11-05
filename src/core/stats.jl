# Detailed statistics (optional, only allocated when needed)
mutable struct DetailedStats
    # 深度分布（每个深度的节点数）
    depth_distribution::Vector{Int}

    # 分支因子历史（每次分支的实际分支数）
    branching_factors::Vector{Int}

    # 传播效率
    propagation_calls::Int
    domain_reductions::Int
    early_unsat_detections::Int

    # 时间细分（秒）
    time_propagation::Float64
    time_branching::Float64
    time_contraction::Float64
    time_filtering::Float64

    # 缓存效率
    cache_hits::Int
    cache_misses::Int

    # 分支决策质量
    variable_selection_counts::Dict{Int, Int}
    remaining_vars_at_branch::Vector{Int}
    depth_at_selection::Vector{Int}  # 每次变量选择时的深度
    variable_selection_sequence::Vector{Int}  # 变量选择序列（按选择顺序）
    successful_paths::Vector{Vector{Int}}  # 成功路径列表（从根到解的变量选择序列）
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

    # 记录详细统计
    if stats.detailed !== nothing
        d = stats.detailed
        push!(d.branching_factors, subproblem_count)

        # 更新深度分布
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

@inline function record_solved_leaf!(stats::BranchingStats, depth::Int, current_path::Vector{Int} = Int[])
    stats.solved_leaves += 1
    record_depth!(stats, depth)
    if stats.detailed !== nothing && !isempty(current_path)
        push!(stats.detailed.successful_paths, copy(current_path))
    end
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

        # 传播统计
        println(io, "\nPropagation:")
        println(io, "  Calls: ", d.propagation_calls)
        println(io, "  Domain reductions: ", d.domain_reductions)
        println(io, "  Early UNSAT detections: ", d.early_unsat_detections)
        if d.propagation_calls > 0
            println(io, "  Avg domains reduced per call: ",
                    round(d.domain_reductions / d.propagation_calls, digits=2))
        end

        # 时间统计
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

        # 缓存统计
        cache_total = d.cache_hits + d.cache_misses
        if cache_total > 0
            println(io, "\nCache efficiency:")
            println(io, "  Hits: ", d.cache_hits)
            println(io, "  Misses: ", d.cache_misses)
            println(io, "  Hit rate: ",
                    round(100 * d.cache_hits / cache_total, digits=1), "%")
        end

        # 分支因子分布
        if !isempty(d.branching_factors)
            println(io, "\nBranching factor distribution:")
            println(io, "  Min: ", minimum(d.branching_factors))
            println(io, "  Max: ", maximum(d.branching_factors))
            println(io, "  Mean: ", round(sum(d.branching_factors) / length(d.branching_factors), digits=2))
            println(io, "  Median: ", median(d.branching_factors))
        end

        # 深度分布
        if !isempty(d.depth_distribution)
            println(io, "\nDepth distribution:")
            # 计算每个深度的累计节点数，用于匹配 branching_factors
            cumulative_nodes = 0
            for (depth_idx, node_count) in enumerate(d.depth_distribution)
                if node_count > 0
                    depth = depth_idx  # 显示时从1开始
                    # 该深度的分支因子范围：从 cumulative_nodes+1 到 cumulative_nodes+node_count
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

        # 变量选择统计
        if !isempty(d.variable_selection_counts)
            println(io, "\nVariable selection (top 10):")
            sorted_vars = sort(collect(d.variable_selection_counts), by=x->x[2], rev=true)
            # 计算每个变量的平均剩余变量数和平均深度
            if !isempty(d.variable_selection_sequence) && 
               length(d.variable_selection_sequence) == length(d.remaining_vars_at_branch) &&
               length(d.variable_selection_sequence) == length(d.depth_at_selection)
                for (var, count) in sorted_vars[1:min(10, length(sorted_vars))]
                    # 找到该变量被选择的所有位置
                    var_indices = [i for (i, v) in enumerate(d.variable_selection_sequence) if v == var]
                    avg_remaining = round(sum(d.remaining_vars_at_branch[i] for i in var_indices) / length(var_indices), digits=1)
                    avg_depth = round(sum(d.depth_at_selection[i] for i in var_indices) / length(var_indices), digits=1)
                    println(io, "  Var ", var, ": ", count, " times, ",
                            "avg remaining vars: ", avg_remaining, ", ",
                            "avg depth: ", avg_depth + 1)
                end
            else
                # 降级显示：只显示选择次数
                for (var, count) in sorted_vars[1:min(10, length(sorted_vars))]
                    println(io, "  Var ", var, ": ", count, " times")
                end
            end
        end

        # 剩余变量分析 - 按深度显示所有选择
        if !isempty(d.remaining_vars_at_branch) && 
           !isempty(d.depth_at_selection) && 
           length(d.depth_at_selection) == length(d.remaining_vars_at_branch)
            # 按深度分组
            depth_remaining = Dict{Int, Vector{Tuple{Int, Int}}}()  # depth -> [(index, remaining_vars), ...]
            for (idx, depth) in enumerate(d.depth_at_selection)
                if !haskey(depth_remaining, depth)
                    depth_remaining[depth] = Tuple{Int, Int}[]
                end
                push!(depth_remaining[depth], (idx, d.remaining_vars_at_branch[idx]))
            end
            
            if !isempty(depth_remaining)
                println(io, "\nRemaining variables at branch:")
                sorted_depths = sort(collect(keys(depth_remaining)))
                for depth in sorted_depths
                    selections = depth_remaining[depth]
                    println(io, "  Depth ", depth + 1, ":")
                    for (idx, remaining_vars) in selections
                        println(io, "    Selection ", idx, ": ", remaining_vars, " remaining vars")
                    end
                end
            end
        end
        
        # 成功路径显示
        if !isempty(d.successful_paths)
            println(io, "\nSuccessful paths:")
            for (path_idx, path) in enumerate(d.successful_paths)
                println(io, "  Path ", path_idx, ": ", join([string(v) for v in path], " -> "))
            end
        end
    end
end
