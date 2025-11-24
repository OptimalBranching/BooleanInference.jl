mutable struct BranchingStats
    total_branches::Int
    total_subproblems::Int
end

BranchingStats() = BranchingStats(0, 0)

function reset!(stats::BranchingStats)
    stats.total_branches = 0
    stats.total_subproblems = 0
    return stats
end

function Base.copy(stats::BranchingStats)
    return BranchingStats(stats.total_branches, stats.total_subproblems)
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

@inline function record_branch!(stats::BranchingStats, subproblem_count::Int)
    stats.total_branches += 1
    stats.total_subproblems += subproblem_count
    return nothing
end

# === Statistics output ===
function print_stats_summary(stats::BranchingStats; io::IO = stdout)
    println(io, "=== Branching Statistics ===")
    println(io, "Total branches: ", stats.total_branches)
    println(io, "Total subproblems: ", stats.total_subproblems)

    # Average branching factor
    if stats.total_branches > 0
        avg_bf = stats.total_subproblems / stats.total_branches
        println(io, "Average branching factor: ", round(avg_bf, digits=2))
    end
end
