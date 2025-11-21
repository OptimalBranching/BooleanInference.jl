mutable struct BranchingStats
    total_branches::Int
    total_subproblems::Int
    max_depth::Int
    solved_leaves::Int
end

BranchingStats() = BranchingStats(0, 0, 0, 0)

function reset!(stats::BranchingStats)
    stats.total_branches = 0
    stats.total_subproblems = 0
    stats.max_depth = 0
    stats.solved_leaves = 0
    return stats
end

function Base.copy(stats::BranchingStats)
    return BranchingStats(
        stats.total_branches,
        stats.total_subproblems,
        stats.max_depth,
        stats.solved_leaves
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

# === Statistics output ===
function print_stats_summary(stats::BranchingStats; io::IO = stdout)
    println(io, "=== Branching Statistics ===")
    println(io, "Branch decisions: ", stats.total_branches)
    println(io, "Child nodes: ", stats.total_subproblems)
    println(io, "Max depth: ", stats.max_depth + 1)
    println(io, "Solved leaves: ", stats.solved_leaves)
    
    # Average branching factor
    if stats.total_branches > 0
        avg_bf = stats.total_subproblems / stats.total_branches
        println(io, "Average branching factor: ", round(avg_bf, digits=2))
    end
end
