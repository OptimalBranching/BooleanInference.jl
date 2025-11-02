# Detailed statistics (optional, only allocated when needed)
mutable struct DetailedStats
    # 深度分布（每个深度的节点数）
    depth_distribution::Vector{Int}

    # 分支因子历史（每次分支的实际分支数）
    branching_factors::Vector{Int}

    # 传播效率
    propagation_calls::Int
    propagation_fixpoints::Int
    domain_reductions::Int
    early_unsat_detections::Int

    # 时间细分（秒）
    time_propagation::Float64
    time_branching::Float64
    time_contraction::Float64

    # 缓存效率
    cache_hits::Int
    cache_misses::Int

    # 分支决策质量
    variable_selection_counts::Dict{Int, Int}
    remaining_vars_at_branch::Vector{Int}
end

DetailedStats() = DetailedStats(
    Int[],
    Int[],
    0, 0, 0, 0,
    0.0, 0.0, 0.0,
    0, 0,
    Dict{Int, Int}(),
    Int[]
)

mutable struct BranchingStats
    # 基础统计（总是记录）
    total_branches::Int
    total_subproblems::Int
    max_depth::Int
    solved_leaves::Int
    unsat_leaves::Int
    skipped_subproblems::Int

    # 详细统计（可选）
    detailed::Union{Nothing, DetailedStats}
end

BranchingStats(verbose::Bool = false) = BranchingStats(
    0, 0, 0, 0, 0, 0,
    verbose ? DetailedStats() : nothing
)

function reset!(stats::BranchingStats)
    stats.total_branches = 0
    stats.total_subproblems = 0
    stats.max_depth = 0
    stats.solved_leaves = 0
    stats.unsat_leaves = 0
    stats.skipped_subproblems = 0

    if stats.detailed !== nothing
        d = stats.detailed
        empty!(d.depth_distribution)
        empty!(d.branching_factors)
        d.propagation_calls = 0
        d.propagation_fixpoints = 0
        d.domain_reductions = 0
        d.early_unsat_detections = 0
        d.time_propagation = 0.0
        d.time_branching = 0.0
        d.time_contraction = 0.0
        d.cache_hits = 0
        d.cache_misses = 0
        empty!(d.variable_selection_counts)
        empty!(d.remaining_vars_at_branch)
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
            d.propagation_fixpoints,
            d.domain_reductions,
            d.early_unsat_detections,
            d.time_propagation,
            d.time_branching,
            d.time_contraction,
            d.cache_hits,
            d.cache_misses,
            copy(d.variable_selection_counts),
            copy(d.remaining_vars_at_branch)
        )
    else
        nothing
    end

    return BranchingStats(
        stats.total_branches,
        stats.total_subproblems,
        stats.max_depth,
        stats.solved_leaves,
        stats.unsat_leaves,
        stats.skipped_subproblems,
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
    stats.unsat_leaves += 1
    record_depth!(stats, depth)
    return nothing
end

@inline function record_solved_leaf!(stats::BranchingStats, depth::Int)
    stats.solved_leaves += 1
    record_depth!(stats, depth)
    return nothing
end

@inline function record_skipped_subproblem!(stats::BranchingStats)
    stats.skipped_subproblems += 1
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

@inline function record_propagation_fixpoint!(stats::BranchingStats)
    if stats.detailed !== nothing
        stats.detailed.propagation_fixpoints += 1
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

@inline function record_variable_selection!(stats::BranchingStats, var::Int, remaining_vars::Int)
    if stats.detailed !== nothing
        d = stats.detailed
        d.variable_selection_counts[var] = get(d.variable_selection_counts, var, 0) + 1
        push!(d.remaining_vars_at_branch, remaining_vars)
    end
    return nothing
end

# === Statistics analysis and visualization ===

"""
    print_stats_summary(stats::BranchingStats; io::IO = stdout)

打印统计信息摘要。
"""
function print_stats_summary(stats::BranchingStats; io::IO = stdout)
    println(io, "=== Branching Statistics ===")
    println(io, "Total branches: ", stats.total_branches)
    println(io, "Total subproblems: ", stats.total_subproblems)
    println(io, "Max depth: ", stats.max_depth)
    println(io, "Solved leaves: ", stats.solved_leaves)
    println(io, "UNSAT leaves: ", stats.unsat_leaves)
    println(io, "Skipped subproblems: ", stats.skipped_subproblems)
    println(io, "Avg branching factor: ", round(stats.avg_branching_factor, digits=3))

    if stats.detailed !== nothing
        println(io, "\n=== Detailed Statistics ===")
        d = stats.detailed

        # 传播统计
        println(io, "\nPropagation:")
        println(io, "  Calls: ", d.propagation_calls)
        println(io, "  Fixpoints: ", d.propagation_fixpoints)
        println(io, "  Domain reductions: ", d.domain_reductions)
        println(io, "  Early UNSAT detections: ", d.early_unsat_detections)
        if d.propagation_calls > 0
            println(io, "  Avg domains reduced per call: ",
                    round(d.domain_reductions / d.propagation_calls, digits=2))
        end

        # 时间统计
        total_time = d.time_propagation + d.time_branching + d.time_contraction
        if total_time > 0
            println(io, "\nTime breakdown:")
            println(io, "  Propagation: ", round(d.time_propagation, digits=3), "s (",
                    round(100 * d.time_propagation / total_time, digits=1), "%)")
            println(io, "  Branching: ", round(d.time_branching, digits=3), "s (",
                    round(100 * d.time_branching / total_time, digits=1), "%)")
            println(io, "  Contraction: ", round(d.time_contraction, digits=3), "s (",
                    round(100 * d.time_contraction / total_time, digits=1), "%)")
            println(io, "  Total: ", round(total_time, digits=3), "s")
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
            for (depth, count) in enumerate(d.depth_distribution)
                if count > 0
                    println(io, "  Depth ", depth - 1, ": ", count, " nodes")
                end
            end
        end

        # 变量选择统计
        if !isempty(d.variable_selection_counts)
            println(io, "\nVariable selection (top 10):")
            sorted_vars = sort(collect(d.variable_selection_counts), by=x->x[2], rev=true)
            for (var, count) in sorted_vars[1:min(10, length(sorted_vars))]
                println(io, "  Var ", var, ": ", count, " times")
            end
        end

        # 剩余变量分析
        if !isempty(d.remaining_vars_at_branch)
            println(io, "\nRemaining variables at branch:")
            println(io, "  Mean: ", round(sum(d.remaining_vars_at_branch) / length(d.remaining_vars_at_branch), digits=1))
            println(io, "  Min: ", minimum(d.remaining_vars_at_branch))
            println(io, "  Max: ", maximum(d.remaining_vars_at_branch))
        end
    end
end

"""
    get_propagation_efficiency(stats::BranchingStats) -> Float64

计算传播效率：每次传播调用平均减少的域数量。
返回 0.0 如果没有详细统计或没有传播调用。
"""
function get_propagation_efficiency(stats::BranchingStats)
    if stats.detailed !== nothing && stats.detailed.propagation_calls > 0
        return stats.detailed.domain_reductions / stats.detailed.propagation_calls
    end
    return 0.0
end

"""
    get_early_unsat_rate(stats::BranchingStats) -> Float64

计算传播早期检测到 UNSAT 的比率。
返回 0.0 如果没有详细统计。
"""
function get_early_unsat_rate(stats::BranchingStats)
    total_unsat = stats.unsat_leaves
    if stats.detailed !== nothing && total_unsat > 0
        return stats.detailed.early_unsat_detections / total_unsat
    end
    return 0.0
end

"""
    get_cache_hit_rate(stats::BranchingStats) -> Float64

计算缓存命中率。
返回 0.0 如果没有详细统计或没有缓存访问。
"""
function get_cache_hit_rate(stats::BranchingStats)
    if stats.detailed !== nothing
        total = stats.detailed.cache_hits + stats.detailed.cache_misses
        if total > 0
            return stats.detailed.cache_hits / total
        end
    end
    return 0.0
end

"""
    get_branching_factor_variance(stats::BranchingStats) -> Float64

计算分支因子的方差。
返回 0.0 如果没有详细统计或没有分支。
"""
function get_branching_factor_variance(stats::BranchingStats)
    if stats.detailed !== nothing && !isempty(stats.detailed.branching_factors)
        bf = stats.detailed.branching_factors
        mean_bf = sum(bf) / length(bf)
        return sum((x - mean_bf)^2 for x in bf) / length(bf)
    end
    return 0.0
end

"""
    median(v::Vector{Int}) -> Float64

计算整数向量的中位数。
"""
function median(v::Vector{Int})
    isempty(v) && return 0.0
    sorted = sort(v)
    n = length(sorted)
    if n % 2 == 1
        return Float64(sorted[div(n, 2) + 1])
    else
        return (sorted[div(n, 2)] + sorted[div(n, 2) + 1]) / 2.0
    end
end

