# ============================================================================
# Common utilities for selectors
# ============================================================================

"""
Sort clauses by branching vector in descending order.
"""
function sort_clauses_by_branching_vector(result)
    clauses = OptimalBranchingCore.get_clauses(result)
    length(clauses) > 1 && (clauses = clauses[sortperm(result.branching_vector, rev=true)])
    return clauses
end

"""
Compute variable selection scores based on weighted occurrence in high-degree tensors.
Score(var) = Σ degree for all tensors containing var with degree > 2
"""
function compute_var_cover_scores_weighted(problem::TNProblem)
    scores = problem.buffer.connection_scores
    fill!(scores, 0.0)
    active_tensors = get_active_tensors(problem.static, problem.doms)

    @inbounds for tensor_id in active_tensors
        vars = problem.static.tensors[tensor_id].var_axes
        degree = count(v -> !is_fixed(problem.doms[v]), vars)
        if degree > 2
            @inbounds for var in vars
                !is_fixed(problem.doms[var]) && (scores[var] += degree)
            end
        end
    end
    return scores
end

"""
Find the unfixed variable with highest score.
Falls back to first unfixed variable if all scores are zero.
"""
function find_best_var_by_score(problem::TNProblem)
    scores = compute_var_cover_scores_weighted(problem)
    max_score, var_id = 0.0, 0
    first_unfixed = 0

    @inbounds for i in eachindex(scores)
        is_fixed(problem.doms[i]) && continue
        first_unfixed == 0 && (first_unfixed = i)
        scores[i] > max_score && (max_score = scores[i]; var_id = i)
    end

    # Fallback to first unfixed variable if no high-score variable found
    var_id == 0 && (var_id = first_unfixed)
    return var_id
end

# ============================================================================
# MostOccurrenceSelector: Fast heuristic based on variable connectivity
# ============================================================================

struct MostOccurrenceSelector <: AbstractSelector
    k::Int
    max_tensors::Int
end

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::MostOccurrenceSelector, depth::Int=0)
    var_id = find_best_var_by_score(problem)
    result, variables = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing, variables
    return sort_clauses_by_branching_vector(result), variables
end

# ============================================================================
# MinGammaSelector: Scan all variables to find minimum γ
# ============================================================================

"""
    MinGammaSelector

Scans ALL unfixed variables to find one with minimum branching factor (γ).
Optimal search tree size but O(num_vars) branching table computations per node.
"""
struct MinGammaSelector <: AbstractSelector
    k::Int
    max_tensors::Int
end

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::MinGammaSelector, depth::Int=0)
    best_γ, best_result, best_variables = Inf, nothing, Int[]

    unfixed_vars = get_unfixed_vars(problem)
    isempty(unfixed_vars) && return nothing, Int[]

    @inbounds for var_id in unfixed_vars
        result, variables = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
        isnothing(result) && continue
        if result.γ < best_γ
            best_γ, best_result, best_variables = result.γ, result, variables
            best_γ == 1.0 && break
        end
    end

    isnothing(best_result) && return nothing, Int[]

    return sort_clauses_by_branching_vector(best_result), best_variables
end

# ============================================================================
# DPLLSelector: Standard 0/1 branching (baseline)
# ============================================================================

"""
    DPLLSelector

Standard DPLL-style branching with 0/1 split. Serves as baseline.
"""
struct DPLLSelector <: AbstractSelector end

function findbest(::RegionCache, problem::TNProblem, ::AbstractMeasure, ::AbstractSetCoverSolver, ::DPLLSelector, depth::Int=0)
    var_id = find_best_var_by_score(problem)
    var_id == 0 && return nothing, Int[]
    clauses = [Clause(UInt64(1), UInt64(0)), Clause(UInt64(1), UInt64(1))]
    return clauses, [var_id]
end

# ============================================================================
# LookaheadSelector: march_cu-style variable selection for cubing
# ============================================================================

"""
    LookaheadSelector

Lookahead-based variable selector inspired by march_cu's approach.
For each candidate variable, simulates both TRUE and FALSE assignments,
propagates constraints, and measures the reduction.

Uses product heuristic: score = reduction_true × reduction_false
This selects variables that cause maximum propagation on both branches,
leading to smaller cubes in Cube-and-Conquer.

# Fields
- `k::Int`: k-neighborhood radius for region computation
- `max_tensors::Int`: Maximum tensors in region
- `n_candidates::Int`: Number of top candidates to evaluate with lookahead
"""
struct LookaheadSelector <: AbstractSelector
    k::Int
    max_tensors::Int
    n_candidates::Int
end

# Default: evaluate top 50 candidates
LookaheadSelector(k::Int, max_tensors::Int) = LookaheadSelector(k, max_tensors, 50)

# ============================================================================
# FixedOrderSelector: Use a pre-specified variable order (for testing/comparison)
# ============================================================================

"""
    FixedOrderSelector

Selector that uses a pre-specified variable order.
Useful for testing with march_cu's variable selection to isolate
the branching method from the variable selection strategy.

# Fields
- `k::Int`: k-neighborhood radius for region computation
- `max_tensors::Int`: Maximum tensors in region
- `var_order::Vector{Int}`: Pre-specified variable order (will select first unfixed)
"""
mutable struct FixedOrderSelector <: AbstractSelector
    k::Int
    max_tensors::Int
    var_order::Vector{Int}
    current_idx::Int
end

FixedOrderSelector(k::Int, max_tensors::Int, var_order::Vector{Int}) =
    FixedOrderSelector(k, max_tensors, var_order, 1)

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::FixedOrderSelector, depth::Int=0)
    # Find the next unfixed variable in the order
    var_id = 0
    while selector.current_idx <= length(selector.var_order)
        candidate = selector.var_order[selector.current_idx]
        if candidate <= length(problem.doms) && !is_fixed(problem.doms[candidate])
            var_id = candidate
            selector.current_idx += 1
            break
        end
        selector.current_idx += 1
    end

    # If no variable from order is available, fall back to MostOccurrence
    if var_id == 0
        var_id = find_best_var_by_score(problem)
    end

    var_id == 0 && return nothing, Int[]

    # Compute branching result for selected variable
    result, variables = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing, variables

    return sort_clauses_by_branching_vector(result), variables
end

"""
    reset!(selector::FixedOrderSelector)

Reset the selector to start from the beginning of the order.
"""
function reset!(selector::FixedOrderSelector)
    selector.current_idx = 1
end

"""
    probe_reduction(problem::TNProblem, measure::AbstractMeasure, var_id::Int, value::Bool) -> Float64

Probe the effect of assigning `var_id = value` and return the measure reduction
after propagation.

Returns -Inf if the assignment leads to a contradiction.
"""
function probe_reduction(problem::TNProblem, measure::AbstractMeasure, var_id::Int, value::Bool)
    buffer = problem.buffer
    doms = problem.doms

    current_measure = measure_core(problem.static, doms, measure)

    vars = [var_id]
    mask = UInt64(1)
    val = value ? UInt64(1) : UInt64(0)

    scratch = probe_assignment_core!(problem, buffer, doms, vars, mask, val)

    scratch[1] == DM_NONE && return -Inf

    new_measure = measure_core(problem.static, scratch, measure)
    return current_measure - new_measure
end

"""
    lookahead_score(reduction_true, reduction_false) -> Float64

March-style product heuristic for variable selection.
Formula: score = left * right + left + right

This maximizes the product of reductions in both branches,
which tends to find variables that cause strong pruning regardless of assignment.
"""
@inline function lookahead_score(reduction_true::Real, reduction_false::Real)
    # March-style product heuristic: left * right + left + right
    left = Float64(reduction_true) + 0.1
    right = Float64(reduction_false) + 0.1
    return 1024.0 * left * right + left + right
end

"""
Compute propagation potential for each variable.
Based on march's diff concept: variables with more implications have higher potential.
We use the number of active tensors connected to the variable as a proxy.
"""
function compute_propagation_potential(problem::TNProblem)
    potential = problem.buffer.connection_scores
    fill!(potential, 0.0)

    @inbounds for var_id in eachindex(problem.doms)
        is_fixed(problem.doms[var_id]) && continue

        # Count active tensors connected to this variable
        for tensor_id in problem.static.v2t[var_id]
            # Weight by tensor degree (more constrained = more propagation)
            vars = problem.static.tensors[tensor_id].var_axes
            unfixed_count = count(v -> !is_fixed(problem.doms[v]), vars)
            if unfixed_count > 0
                potential[var_id] += 1.0 / unfixed_count
            end
        end
    end

    return potential
end

"""
Select top candidates by propagation potential for look-ahead.
Similar to march's preselection by diff rank.
"""
function select_lookahead_candidates(problem::TNProblem, n_candidates::Int)
    unfixed_vars = get_unfixed_vars(problem)
    n = length(unfixed_vars)

    n_candidates <= 0 && return unfixed_vars
    n_candidates >= n && return unfixed_vars

    # Compute propagation potential
    potential = compute_propagation_potential(problem)

    # Sort by potential (descending) and take top candidates
    sorted_vars = sort(unfixed_vars, by=v -> potential[v], rev=true)
    return sorted_vars[1:min(n_candidates, n)]
end

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::LookaheadSelector, depth::Int=0)
    unfixed_vars = get_unfixed_vars(problem)
    isempty(unfixed_vars) && return nothing, Int[]

    # Select candidates by propagation potential (march-style preselection)
    candidates = select_lookahead_candidates(problem, selector.n_candidates)

    best_score = -Inf
    best_var = candidates[1]
    forced_score = -Inf
    forced_var = 0
    forced_value = false

    @inbounds for var_id in candidates
        reduction_true = probe_reduction(problem, measure, var_id, true)
        reduction_false = probe_reduction(problem, measure, var_id, false)

        if reduction_true == -Inf && reduction_false == -Inf
            return nothing, Int[]
        elseif reduction_true == -Inf || reduction_false == -Inf
            feasible_reduction = reduction_true == -Inf ? reduction_false : reduction_true
            if feasible_reduction > forced_score
                forced_score = feasible_reduction
                forced_var = var_id
                forced_value = reduction_true == -Inf ? false : true
            end
            continue
        end

        score = lookahead_score(reduction_true, reduction_false)
        if score > best_score
            best_score = score
            best_var = var_id
        end
    end

    if forced_var != 0
        clause = forced_value ? Clause(UInt64(1), UInt64(1)) : Clause(UInt64(1), UInt64(0))
        return [clause], [forced_var]
    end

    result, variables = compute_branching_result(cache, problem, best_var, measure, set_cover_solver)
    isnothing(result) && return nothing, variables

    return sort_clauses_by_branching_vector(result), variables
end
