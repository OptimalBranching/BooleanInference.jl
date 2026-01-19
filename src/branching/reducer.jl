# ============================================================================
# Gamma-One Reducer
#
# Implements a reduction strategy that exhaustively applies forced variable
# assignments (gamma=1 regions) before branching.
# ============================================================================

"""
    GammaOneReducer <: AbstractReducer

A reducer that finds and applies gamma=1 regions (forced variable assignments).

When a region has gamma=1, it means there exists a variable with a unique
feasible value across all configurations. Applying such assignments reduces
the problem size without introducing branching.

# Fields
- `limit::Int`: Maximum variables to scan per reduction pass (0 = scan all)

# Algorithm
1. Sort variables by connectivity score (high-impact first)
2. For each variable, check if its region has a forced assignment
3. If found, apply it in-place and continue scanning
4. Re-sort and repeat until no gamma=1 regions exist (saturation)
"""
struct GammaOneReducer <: OptimalBranchingCore.AbstractReducer
    limit::Int
end

GammaOneReducer() = GammaOneReducer(10)

# ============================================================================
# Variable Sorting Utilities
# ============================================================================

"""
    get_sorted_unfixed_vars(problem) -> Vector{Int}

Get unfixed variables sorted by connectivity score (high-impact first).

Returns a NEW vector (safe to store) sorted by score.
Uses scratch buffer internally to reduce allocations.
"""
function get_sorted_unfixed_vars(problem::TNProblem)
    scratch = problem.buffer.scratch_vars
    empty!(scratch)
    
    @inbounds for (i, dm) in enumerate(problem.doms)
        !is_fixed(dm) && push!(scratch, i)
    end
    
    isempty(scratch) && return Int[]
    
    scores = compute_var_cover_scores_weighted(problem)
    sort!(scratch, by=v -> @inbounds(scores[v]), rev=true)
    return copy(scratch)
end

# ============================================================================
# OptimalBranchingCore Interface
# ============================================================================

"""
    OptimalBranchingCore.reduce_problem(::Type{T}, problem, reducer) -> (problem, gain)

Standard OptimalBranchingCore interface implementation.

Note: The full reduction logic is in `reduce_with_gamma_one!` (branch.jl),
which has access to the SearchContext. This method is a no-op placeholder.
"""
function OptimalBranchingCore.reduce_problem(::Type{T}, problem::TNProblem, reducer::GammaOneReducer) where T
    return (problem, zero(T))
end
