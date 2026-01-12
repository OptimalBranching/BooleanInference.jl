# ============================================================================
# Gamma-One Reducer
#
# Implements a reduction strategy that exhaustively applies forced variable
# assignments (gamma=1 regions) before branching. This separates reduction
# logic from branching logic for cleaner algorithm design.
# ============================================================================

"""
    GammaOneReducer <: AbstractReducer

A reducer that finds and applies gamma=1 regions (forced variable assignments).

When a region has gamma=1, it means there exists a variable with a unique
feasible value across all configurations. Applying such assignments reduces
the problem size without introducing branching.

# Fields
- `limit::Int`: Maximum variables to scan per reduction pass (0 = scan all)

# Note
The reducer shares the region cache with the selector, so region size parameters
(k, max_tensors) are determined by the selector configuration.

# Algorithm
1. Sort variables by connectivity score (high-impact first)
2. For each variable, check if its region has a forced assignment
3. If found, apply it and repeat
4. Continue until no gamma=1 regions exist (saturation)
"""
struct GammaOneReducer <: OptimalBranchingCore.AbstractReducer
    limit::Int
end

GammaOneReducer() = GammaOneReducer(10)

# ============================================================================
# Gamma-One Detection
# ============================================================================

"""
    find_gamma_one_region(cache, problem, measure, reducer) -> Union{Nothing, Tuple}

Scan variables to find a region with gamma=1 (forced assignment).

This function is optimized for the reduction phase:
- Uses `find_forced_assignment` which only checks for gamma=1
- Does NOT compute GreedyMerge when no forced variable is found
- Much faster than using `compute_branching_result`

Returns `nothing` if no gamma=1 region exists, otherwise returns
`(clause, variables)` for the forced assignment.

Note: The `set_cover_solver` parameter is not needed here since we
only check for gamma=1 (no branching rule computation).
"""
function find_gamma_one_region(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, reducer::GammaOneReducer)
    unfixed_vars = get_unfixed_vars(problem)
    isempty(unfixed_vars) && return nothing

    # Sort by connectivity score (high-impact variables first)
    scores = compute_var_cover_scores_weighted(problem)
    sorted_vars = sort(unfixed_vars, by=v -> scores[v], rev=true)

    # Scan for gamma=1
    n_vars = length(sorted_vars)
    scan_limit = reducer.limit == 0 ? n_vars : min(n_vars, reducer.limit)

    @inbounds for i in 1:scan_limit
        var_id = sorted_vars[i]

        # Use find_forced_assignment - fast path only, no GreedyMerge
        result = find_forced_assignment(cache, problem, var_id, measure)

        if !isnothing(result)
            clause, variables = result
            return ([clause], variables)  # Wrap clause in array for consistency
        end
    end
    return nothing
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
