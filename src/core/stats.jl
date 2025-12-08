mutable struct BranchingStats
    branching_nodes::Int              # Number of branching decisions
    total_potential_subproblems::Int # All generated subproblems (potential)
    total_visited_nodes::Int         # Actually explored nodes
end

BranchingStats() = BranchingStats(0, 0, 0)

function reset!(stats::BranchingStats)
    stats.branching_nodes = 0
    stats.total_potential_subproblems = 0
    stats.total_visited_nodes = 0
    return stats
end

function Base.copy(stats::BranchingStats)
    return BranchingStats(stats.branching_nodes, stats.total_potential_subproblems, stats.total_visited_nodes)
end

function Base.getproperty(stats::BranchingStats, name::Symbol)
    if name === :avg_branching_factor
        return stats.branching_nodes > 0 ?
            stats.total_potential_subproblems / stats.branching_nodes :
            0.0
    elseif name === :avg_actual_branches
        return stats.branching_nodes > 0 ?
            stats.total_visited_nodes / stats.branching_nodes :
            0.0
    else
        return getfield(stats, name)
    end
end

function Base.propertynames(::BranchingStats; private::Bool=false)
    return (fieldnames(BranchingStats)..., :avg_branching_factor, :avg_actual_branches, :pruning_rate, :total_subproblems)
end

@inline function record_branch!(stats::BranchingStats, subproblem_count::Int)
    stats.branching_nodes += 1
    stats.total_potential_subproblems += subproblem_count
    return nothing
end

@inline function record_visit!(stats::BranchingStats)
    stats.total_visited_nodes += 1
    return nothing
end

# === Statistics output ===
function print_stats_summary(stats::BranchingStats; io::IO = stdout)
    println(io, "=== Branching Statistics ===")
    println(io, "Branching nodes: ", stats.branching_nodes)
    println(io, "Total potential subproblems: ", stats.total_potential_subproblems)
    println(io, "Total visited nodes: ", stats.total_visited_nodes)

    # Average branching factor (potential)
    if stats.branching_nodes > 0
        avg_bf = stats.total_potential_subproblems / stats.branching_nodes
        println(io, "Average branching factor (potential): ", round(avg_bf, digits=2))

        avg_actual = stats.total_visited_nodes / stats.branching_nodes
        println(io, "Average branching factor (actual): ", round(avg_actual, digits=2))
    end
end
