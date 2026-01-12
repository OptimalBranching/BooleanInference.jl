mutable struct BranchingStats
    branch_points::Int           # Number of γ>1 branching points
    gamma_one_count::Int         # Number of γ=1 reductions applied
    branches_generated::Int      # Total branches generated (sum of branch counts at each point)
    branches_explored::Int       # Total branches actually explored (THIS is "branches" for comparison)
    dead_ends::Int               # Branches that led to UNSAT (conflicts/backtrack)
    direct_vars_by_branches::Int # Direct variables assigned by branching clauses (for avg_vars_per_branch)
    vars_by_branches::Int        # Variables fixed by γ>1 branches (direct + propagated, for Table 2)
    vars_by_gamma_one::Int       # Variables fixed by γ=1 reductions (direct + propagated, for Table 2)
    direct_vars_by_gamma_one::Int # Variables directly forced by γ=1 contraction (NOT by subsequent propagation)
end

BranchingStats() = BranchingStats(0, 0, 0, 0, 0, 0, 0, 0, 0)

function reset!(stats::BranchingStats)
    stats.branch_points = 0
    stats.gamma_one_count = 0
    stats.branches_generated = 0
    stats.branches_explored = 0
    stats.dead_ends = 0
    stats.direct_vars_by_branches = 0
    stats.vars_by_branches = 0
    stats.vars_by_gamma_one = 0
    stats.direct_vars_by_gamma_one = 0
    return stats
end

function Base.copy(stats::BranchingStats)
    return BranchingStats(
        stats.branch_points, stats.gamma_one_count,
        stats.branches_generated, stats.branches_explored, stats.dead_ends,
        stats.direct_vars_by_branches, stats.vars_by_branches, stats.vars_by_gamma_one,
        stats.direct_vars_by_gamma_one
    )
end

function Base.getproperty(stats::BranchingStats, name::Symbol)
    if name === :avg_branching_factor
        return stats.branch_points > 0 ?
            stats.branches_generated / stats.branch_points : 0.0
    elseif name === :avg_branches_per_point
        return stats.branch_points > 0 ?
            stats.branches_explored / stats.branch_points : 0.0
    elseif name === :avg_vars_per_branch
        # Use direct vars only (not propagated) for Table 1
        return stats.branches_explored > 0 ?
            stats.direct_vars_by_branches / stats.branches_explored : 0.0
    else
        return getfield(stats, name)
    end
end

function Base.propertynames(::BranchingStats; private::Bool=false)
    return (fieldnames(BranchingStats)..., :avg_branching_factor, :avg_branches_per_point, :avg_vars_per_branch)
end

@inline function record_branch_point!(stats::BranchingStats, branch_count::Int)
    stats.branch_points += 1
    stats.branches_generated += branch_count
    return nothing
end

@inline function record_branch_explored!(stats::BranchingStats, direct_vars::Int=0, total_vars_fixed::Int=0)
    stats.branches_explored += 1
    stats.direct_vars_by_branches += direct_vars
    stats.vars_by_branches += total_vars_fixed
    return nothing
end

@inline function record_gamma_one!(stats::BranchingStats, direct_vars::Int=0, total_vars_fixed::Int=0)
    stats.gamma_one_count += 1
    stats.direct_vars_by_gamma_one += direct_vars
    stats.vars_by_gamma_one += total_vars_fixed
    return nothing
end

@inline function record_dead_end!(stats::BranchingStats)
    stats.dead_ends += 1
    return nothing
end

# === Statistics output ===
function print_stats_summary(stats::BranchingStats; io::IO = stdout)
    println(io, "=== Branching Statistics ===")
    println(io, "γ=1 reductions: ", stats.gamma_one_count)
    println(io, "γ>1 branch points: ", stats.branch_points)
    println(io, "Branches generated: ", stats.branches_generated)
    println(io, "Branches explored: ", stats.branches_explored)
    println(io, "Dead ends (conflicts): ", stats.dead_ends)
    println(io, "Vars fixed by γ=1 (total): ", stats.vars_by_gamma_one)
    println(io, "  - Direct by contraction: ", stats.direct_vars_by_gamma_one)
    println(io, "  - By propagation after: ", stats.vars_by_gamma_one - stats.direct_vars_by_gamma_one)
    println(io, "Vars fixed by branches: ", stats.vars_by_branches)

    if stats.branch_points > 0
        println(io, "Avg branching factor: ", round(stats.avg_branching_factor, digits=2))
        println(io, "Avg branches explored per point: ", round(stats.avg_branches_per_point, digits=2))
    end
    if stats.branches_explored > 0
        println(io, "Avg vars per branch: ", round(stats.avg_vars_per_branch, digits=2))
    end

    # γ=1 ratio (by variable count)
    total_vars = stats.vars_by_gamma_one + stats.vars_by_branches
    if total_vars > 0
        ratio = stats.vars_by_gamma_one / total_vars * 100
        println(io, "γ=1 vars ratio: ", round(ratio, digits=1), "%")
    end

    # Direct contraction contribution
    if stats.direct_vars_by_gamma_one > 0
        direct_ratio = stats.direct_vars_by_gamma_one / total_vars * 100
        println(io, "Direct contraction ratio: ", round(direct_ratio, digits=1), "%")
    end
end
