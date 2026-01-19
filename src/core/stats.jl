"""
BranchingStats: Statistics for branch-and-bound SAT solving

Node classification (mutually exclusive & exhaustive):
- Branching nodes: k≥2 children generated
- Reduction nodes: γ=1, single successor with non-trivial reduction  
- Terminal nodes: no children (SAT or UNSAT leaves)
"""
mutable struct BranchingStats
    # ---- node counts (mutually exclusive) ----
    total_nodes::Int
    branching_nodes::Int
    reduction_nodes::Int
    terminal_nodes::Int

    # ---- leaf types ----
    sat_leaves::Int
    unsat_leaves::Int

    # ---- edges / children ----
    children_generated::Int
    children_explored::Int

    # ---- assignments by source ----
    branch_decision_assignments::Int   # direct vars assigned by branching clause
    branch_implied_assignments::Int    # vars propagated after branch decision

    reduction_direct_assignments::Int  # direct vars from γ=1 contraction
    reduction_implied_assignments::Int # vars propagated after γ=1 reduction

    # ---- gamma trace (for γ-landscape analysis) ----
    gamma_trace::Vector{Float64}       # γ value at each decision point

    # ---- measure trace (for progress tracking) ----
    measure_trace::Vector{Float64}     # measure value at each decision point

    # ---- table size trace (for overhead analysis) ----
    table_configs_trace::Vector{Int}   # number of configs in table at each branching
    table_vars_trace::Vector{Int}      # number of unfixed vars at each branching
end

BranchingStats() = BranchingStats(
    0, 0, 0, 0,
    0, 0,
    0, 0,
    0, 0,
    0, 0,
    Float64[],
    Float64[],
    Int[],
    Int[]
)

function reset!(stats::BranchingStats)
    stats.total_nodes = 0
    stats.branching_nodes = 0
    stats.reduction_nodes = 0
    stats.terminal_nodes = 0

    stats.sat_leaves = 0
    stats.unsat_leaves = 0

    stats.children_generated = 0
    stats.children_explored = 0

    stats.branch_decision_assignments = 0
    stats.branch_implied_assignments = 0
    stats.reduction_direct_assignments = 0
    stats.reduction_implied_assignments = 0

    empty!(stats.gamma_trace)
    empty!(stats.measure_trace)
    empty!(stats.table_configs_trace)
    empty!(stats.table_vars_trace)
    return stats
end

function Base.copy(stats::BranchingStats)
    return BranchingStats(
        stats.total_nodes,
        stats.branching_nodes,
        stats.reduction_nodes,
        stats.terminal_nodes,

        stats.sat_leaves,
        stats.unsat_leaves,

        stats.children_generated,
        stats.children_explored,

        stats.branch_decision_assignments,
        stats.branch_implied_assignments,
        stats.reduction_direct_assignments,
        stats.reduction_implied_assignments,

        copy(stats.gamma_trace),
        copy(stats.measure_trace),
        copy(stats.table_configs_trace),
        copy(stats.table_vars_trace)
    )
end

# ---- computed properties ----
function Base.getproperty(stats::BranchingStats, name::Symbol)
    if name === :avg_gamma
        return stats.branching_nodes > 0 ?
            stats.children_generated / stats.branching_nodes : 0.0
    elseif name === :avg_vars_per_branch
        return stats.children_explored > 0 ?
            stats.branch_decision_assignments / stats.children_explored : 0.0
    elseif name === :total_assignments
        return stats.branch_decision_assignments + stats.branch_implied_assignments +
               stats.reduction_direct_assignments + stats.reduction_implied_assignments
    elseif name === :avg_table_configs
        trace = getfield(stats, :table_configs_trace)
        return isempty(trace) ? 0.0 : sum(trace) / length(trace)
    elseif name === :avg_table_vars
        trace = getfield(stats, :table_vars_trace)
        return isempty(trace) ? 0.0 : sum(trace) / length(trace)
    elseif name === :max_table_configs
        trace = getfield(stats, :table_configs_trace)
        return isempty(trace) ? 0 : maximum(trace)
    else
        return getfield(stats, name)
    end
end

function Base.propertynames(::BranchingStats; private::Bool=false)
    return (fieldnames(BranchingStats)..., :avg_gamma, :avg_vars_per_branch, :total_assignments,
            :avg_table_configs, :avg_table_vars, :max_table_configs)
end

# ============================================================================
# Recording functions
# ============================================================================

"""Record a SAT leaf (terminal node, problem solved)"""
@inline function record_sat_leaf!(stats::BranchingStats)
    stats.total_nodes += 1
    stats.terminal_nodes += 1
    stats.sat_leaves += 1
    return nothing
end

"""Record an UNSAT leaf (terminal node, conflict/dead-end)"""
@inline function record_unsat_leaf!(stats::BranchingStats)
    stats.total_nodes += 1
    stats.terminal_nodes += 1
    stats.unsat_leaves += 1
    return nothing
end

"""Record a branching node (k≥2 children)"""
@inline function record_branching_node!(stats::BranchingStats, k::Int)
    stats.total_nodes += 1
    stats.branching_nodes += 1
    stats.children_generated += k
    return nothing
end

"""Record a reduction-only node (γ=1, single successor)"""
@inline function record_reduction_node!(stats::BranchingStats)
    stats.total_nodes += 1
    stats.reduction_nodes += 1
    return nothing
end

"""Record a child being explored (branch taken)"""
@inline function record_child_explored!(stats::BranchingStats, direct_vars::Int, implied_vars::Int)
    stats.children_explored += 1
    stats.branch_decision_assignments += direct_vars
    stats.branch_implied_assignments += implied_vars
    return nothing
end

"""Record a γ=1 reduction applied"""
@inline function record_reduction!(stats::BranchingStats, direct_vars::Int, implied_vars::Int)
    stats.reduction_direct_assignments += direct_vars
    stats.reduction_implied_assignments += implied_vars
    return nothing
end

"""Record γ value at a decision point (for γ-landscape tracing)"""
@inline function record_gamma!(stats::BranchingStats, gamma::Float64)
    push!(stats.gamma_trace, gamma)
    return nothing
end

"""Record measure value at a decision point (for progress tracking)"""
@inline function record_measure!(stats::BranchingStats, measure_val::Float64)
    push!(stats.measure_trace, measure_val)
    return nothing
end

"""Record table size at a branching point (for overhead analysis)"""
@inline function record_table_size!(stats::BranchingStats, n_configs::Int, n_vars::Int)
    push!(stats.table_configs_trace, n_configs)
    push!(stats.table_vars_trace, n_vars)
    return nothing
end

# ============================================================================
# Statistics output
# ============================================================================
function print_stats_summary(stats::BranchingStats; io::IO = stdout)
    println(io, "=== Branching Statistics ===")
    
    # Node counts
    println(io, "--- Nodes (mutually exclusive) ---")
    println(io, "Total nodes: ", stats.total_nodes)
    println(io, "  Branching nodes (k≥2): ", stats.branching_nodes)
    println(io, "  Reduction nodes (γ=1): ", stats.reduction_nodes)
    println(io, "  Terminal nodes: ", stats.terminal_nodes)
    println(io, "    - SAT leaves: ", stats.sat_leaves)
    println(io, "    - UNSAT leaves: ", stats.unsat_leaves)

    # Edges
    println(io, "--- Edges / Children ---")
    println(io, "Children generated: ", stats.children_generated)
    println(io, "Children explored: ", stats.children_explored)
    if stats.branching_nodes > 0
        println(io, "Avg γ (branching factor): ", round(stats.avg_gamma, digits=3))
    end

    # Assignments
    println(io, "--- Assignments ---")
    println(io, "By branching:")
    println(io, "  Decision (direct): ", stats.branch_decision_assignments)
    println(io, "  Implied (propagated): ", stats.branch_implied_assignments)
    println(io, "By reduction:")
    println(io, "  Direct: ", stats.reduction_direct_assignments)
    println(io, "  Implied (propagated): ", stats.reduction_implied_assignments)
    println(io, "Total assignments: ", stats.total_assignments)

    # Ratios
    total = stats.total_assignments
    if total > 0
        branch_total = stats.branch_decision_assignments + stats.branch_implied_assignments
        reduction_total = stats.reduction_direct_assignments + stats.reduction_implied_assignments
        println(io, "--- Ratios ---")
        println(io, "Branch assignments: ", round(100 * branch_total / total, digits=1), "%")
        println(io, "Reduction assignments: ", round(100 * reduction_total / total, digits=1), "%")
    end
end
