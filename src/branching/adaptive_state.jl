# ============================================================================
# Adaptive State for Learning from CDCL Feedback
#
# Shared by different dual-process approaches to maintain learned knowledge
# about variable difficulties and interactions.
# ============================================================================

"""
    AdaptiveState

Mutable state that learns from CDCL feedback.

Maintains learned difficulties and statistics to guide future decisions.
"""
mutable struct AdaptiveState
    var_difficulty::Vector{Float64}          # Per-variable difficulty scores
    edge_hardness::Dict{Tuple{Int,Int}, Float64}  # Pairwise interaction hardness
    total_cdcl_calls::Int
    total_cdcl_conflicts::Int
    alpha::Float64  # Learning rate
    enabled::Bool   # Whether adaptive learning is enabled

    function AdaptiveState(nvars::Int; alpha::Float64=0.1, enabled::Bool=true)
        new(
            ones(Float64, nvars),  # Initialize with uniform difficulty
            Dict{Tuple{Int,Int}, Float64}(),
            0, 0,
            alpha, enabled
        )
    end
end

"""
    update_from_cdcl_feedback!(
        state::AdaptiveState,
        assigned_vars::Vector{Int},
        feedback::CDCLFeedback
    )

Update adaptive state based on CDCL feedback.

Learning rules:
- UNSAT with UNSAT core → Increase difficulty of variables in core
- SAT with low conflicts → Slightly decrease difficulty (reward)
- High conflicts → Mark variables as hard regardless of outcome
- Update edge hardness for variable pairs in UNSAT cores
"""
function update_from_cdcl_feedback!(
    state::AdaptiveState,
    assigned_vars::Vector{Int},
    feedback::CDCLFeedback
)
    !state.enabled && return

    state.total_cdcl_calls += 1
    state.total_cdcl_conflicts += feedback.conflicts

    if feedback.status == :unsat && !isempty(feedback.unsat_core)
        # UNSAT: Increase difficulty of variables in UNSAT core
        for lit in feedback.unsat_core
            var = abs(lit)
            if var <= length(state.var_difficulty)
                state.var_difficulty[var] *= (1.0 + state.alpha * 2.0)
            end
        end

        # Update edge hardness for pairs in UNSAT core
        for i in 1:length(feedback.unsat_core)
            for j in (i+1):length(feedback.unsat_core)
                v1, v2 = abs(feedback.unsat_core[i]), abs(feedback.unsat_core[j])
                v1 > v2 && ((v1, v2) = (v2, v1))
                edge = (v1, v2)
                current = get(state.edge_hardness, edge, 1.0)
                state.edge_hardness[edge] = current * (1.0 + state.alpha * 1.5)
            end
        end

    elseif feedback.status == :sat && feedback.conflicts < 5
        # SAT with low conflicts: slightly decrease difficulty (reward)
        for var in assigned_vars
            if var <= length(state.var_difficulty)
                state.var_difficulty[var] *= (1.0 - state.alpha * 0.3)
                state.var_difficulty[var] = max(0.1, state.var_difficulty[var])
            end
        end
    end

    # High conflicts indicate difficult region
    if feedback.conflicts > 10
        conflict_factor = min(feedback.conflicts / 10.0, 3.0)
        for var in assigned_vars
            if var <= length(state.var_difficulty)
                state.var_difficulty[var] *= (1.0 + state.alpha * conflict_factor * 0.3)
            end
        end
    end
end

"""
    print_adaptive_stats(adaptive_state::AdaptiveState)

Print statistics about adaptive learning.
"""
function print_adaptive_stats(adaptive_state::AdaptiveState)
    println("\n=== Adaptive Learning Statistics ===")
    println("CDCL calls: ", adaptive_state.total_cdcl_calls)
    println("Total conflicts: ", adaptive_state.total_cdcl_conflicts)

    if adaptive_state.total_cdcl_calls > 0
        println("Avg conflicts/call: ",
                round(adaptive_state.total_cdcl_conflicts / adaptive_state.total_cdcl_calls, digits=2))
    end

    # Show top difficult variables
    difficulties = adaptive_state.var_difficulty
    sorted_idx = sortperm(difficulties, rev=true)

    println("\nTop 10 difficult variables:")
    for i in 1:min(10, length(sorted_idx))
        var = sorted_idx[i]
        println("  x$var: ", round(difficulties[var], digits=3))
    end

    println("\nEdge hardness entries: ", length(adaptive_state.edge_hardness))
    println("====================================\n")
end
