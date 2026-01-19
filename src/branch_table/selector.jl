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
    result, variables, table_info = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing, variables, nothing, table_info
    return sort_clauses_by_branching_vector(result), variables, result.γ, table_info
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
    var_id == 0 && return nothing, Int[], nothing, (n_configs=0, n_vars=0)
    clauses = [Clause(UInt64(1), UInt64(0)), Clause(UInt64(1), UInt64(1))]
    return clauses, [var_id], 2.0, (n_configs=2, n_vars=1)
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
    limit::Int
end

"""
Select top candidates by connectivity score for MinGammaSelector.
Returns unfixed variables sorted by their connection score (descending), limited to n_candidates.
"""
function select_high_connectivity_candidates(problem::TNProblem, n_candidates::Int)
    unfixed_vars = get_unfixed_vars(problem)
    n = length(unfixed_vars)
    
    n_candidates <= 0 && return unfixed_vars
    n_candidates >= n && return unfixed_vars
    
    # Use weighted connection scores
    scores = compute_var_cover_scores_weighted(problem)
    
    # Sort by score (descending) and take top candidates
    sorted_vars = sort(unfixed_vars, by=v -> scores[v], rev=true)
    return sorted_vars[1:min(n_candidates, n)]
end

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::MinGammaSelector, ::Int=0)
    best_γ, best_result, best_variables = Inf, nothing, Int[]
    best_table_info = (n_configs=0, n_vars=0)

    unfixed_vars = get_unfixed_vars(problem)
    isempty(unfixed_vars) && return nothing, Int[], nothing, best_table_info

    # When limit == 0, scan all variables (skip connectivity score computation)
    candidates = selector.limit == 0 ? unfixed_vars : select_high_connectivity_candidates(problem, selector.limit)

    @inbounds for var_id in candidates
        result, variables, table_info = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
        isnothing(result) && continue
        # result.γ == 1.0 && continue
        if result.γ < best_γ
            best_γ, best_result, best_variables = result.γ, result, variables
            best_table_info = table_info
            best_γ == 1.0 && break
        end
    end
    isnothing(best_result) && return nothing, Int[], nothing, best_table_info

    return sort_clauses_by_branching_vector(best_result), best_variables, best_γ, best_table_info
end

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
FixedOrderSelector(k::Int, max_tensors::Int, var_order::Vector{Int}) = FixedOrderSelector(k, max_tensors, var_order, 1)

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::FixedOrderSelector, ::Int=0)
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

    var_id == 0 && return nothing, Int[], nothing, (n_configs=0, n_vars=0)

    # Compute branching result for selected variable
    result, variables, table_info = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing, variables, nothing, table_info

    return sort_clauses_by_branching_vector(result), variables, result.γ, table_info
end

"""
    reset!(selector::FixedOrderSelector)

Reset the selector to start from the beginning of the order.
"""
function reset!(selector::FixedOrderSelector)
    selector.current_idx = 1
end

# ============================================================================
# FixedOrderDPLLSelector: Use a pre-specified variable order with DPLL branching
# ============================================================================

"""
    FixedOrderDPLLSelector

Selector that uses a pre-specified variable order with standard DPLL-style 0/1 branching.
Useful for testing with march_cu's variable selection while using simple DPLL branching.

# Fields
- `var_order::Vector{Int}`: Pre-specified variable order (will select first unfixed)
"""
mutable struct FixedOrderDPLLSelector <: AbstractSelector
    var_order::Vector{Int}
    current_idx::Int
end
FixedOrderDPLLSelector(var_order::Vector{Int}) = FixedOrderDPLLSelector(var_order, 1)

function findbest(::RegionCache, problem::TNProblem, ::AbstractMeasure, ::AbstractSetCoverSolver, selector::FixedOrderDPLLSelector, ::Int=0)
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

    var_id == 0 && return nothing, Int[], nothing, (n_configs=0, n_vars=0)

    # Return standard DPLL 0/1 branching
    clauses = [Clause(UInt64(1), UInt64(0)), Clause(UInt64(1), UInt64(1))]
    return clauses, [var_id], 2.0, (n_configs=2, n_vars=1)
end

"""
    reset!(selector::FixedOrderDPLLSelector)

Reset the selector to start from the beginning of the order.
"""
function reset!(selector::FixedOrderDPLLSelector)
    selector.current_idx = 1
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

"""
    probe_implied_count(problem::TNProblem, var_id::Int, value::Bool) -> Int

Probe the effect of assigning `var_id = value` and return the number of
**implied variables** (variables fixed by propagation, NOT including the decision).

Returns -1 if the assignment leads to a contradiction.

This is the key metric in march_cu: variables that cause more implications
lead to easier subproblems.
"""
function probe_implied_count(problem::TNProblem, var_id::Int, value::Bool)
    buffer = problem.buffer
    doms = problem.doms

    current_unfixed = count_unfixed(doms)

    vars = [var_id]
    mask = UInt64(1)
    val = value ? UInt64(1) : UInt64(0)

    scratch = probe_assignment_core!(problem, buffer, doms, vars, mask, val)

    # Contradiction
    scratch[1] == DM_NONE && return -1

    new_unfixed = count_unfixed(scratch)
    # implied = (current - new) - 1 (subtract the decision variable itself)
    return (current_unfixed - new_unfixed) - 1
end

"""
    lookahead_score(implied_true, implied_false) -> Float64

March-style product heuristic for variable selection.
Formula: score = (left + 0.1) * (right + 0.1) * 1024 + left + right

Maximizes the product of implications on both branches.
Variables with balanced, high implications → smaller search tree.
"""
@inline function lookahead_score(implied_true::Int, implied_false::Int)
    left = Float64(implied_true) + 0.1
    right = Float64(implied_false) + 0.1
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
    isempty(unfixed_vars) && return nothing, Int[], nothing, (n_configs=0, n_vars=0)

    # Select candidates by propagation potential (march-style preselection)
    candidates = select_lookahead_candidates(problem, selector.n_candidates)

    # Phase 1: Lookahead evaluation to filter candidates
    lookahead_scores = Float64[]
    candidate_vars = Int[]
    forced_var = 0
    forced_value = false
    best_forced_implied = -1

    @inbounds for var_id in candidates
        implied_true = probe_implied_count(problem, var_id, true)
        implied_false = probe_implied_count(problem, var_id, false)

        # Both branches contradict - problem is UNSAT
        if implied_true == -1 && implied_false == -1
            return nothing, Int[], nothing, (n_configs=0, n_vars=0)
        end

        # One branch contradicts - this is a forced assignment (failed literal)
        if implied_true == -1 || implied_false == -1
            feasible_implied = implied_true == -1 ? implied_false : implied_true
            if feasible_implied > best_forced_implied
                best_forced_implied = feasible_implied
                forced_var = var_id
                forced_value = implied_true == -1 ? false : true
            end
            continue
        end

        # Both branches feasible - use product heuristic
        score = lookahead_score(implied_true, implied_false)
        push!(lookahead_scores, score)
        push!(candidate_vars, var_id)
    end

    # If we found a forced assignment, return it as a single-branch clause
    if forced_var != 0
        clause = forced_value ? Clause(UInt64(1), UInt64(1)) : Clause(UInt64(1), UInt64(0))
        return [clause], [forced_var], 1.0, (n_configs=1, n_vars=1)
    end

    isempty(candidate_vars) && return nothing, Int[], nothing, (n_configs=0, n_vars=0)

    # Phase 2: For top candidates by lookahead score, evaluate GreedyMerge optimization
    # Select top candidates (top 10 or all if fewer) for GreedyMerge evaluation
    n_eval = min(10, length(candidate_vars))
    sorted_indices = sortperm(lookahead_scores, rev=true)
    top_candidates = candidate_vars[sorted_indices[1:n_eval]]

    best_γ = Inf
    best_result = nothing
    best_variables = Int[]
    best_table_info = (n_configs=0, n_vars=0)

    @inbounds for var_id in top_candidates
        result, variables, table_info = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
        isnothing(result) && continue

        # Select variable with minimum γ after GreedyMerge optimization
        if result.γ < best_γ
            best_γ = result.γ
            best_result = result
            best_variables = variables
            best_table_info = table_info
            best_γ == 1.0 && break  # Early termination if we find γ=1
        end
    end

    isnothing(best_result) && return nothing, Int[], nothing, best_table_info

    return sort_clauses_by_branching_vector(best_result), best_variables, best_γ, best_table_info
end
