struct LeastOccurrenceSelector <: AbstractSelector end

function OptimalBranchingCore.select_variables(
    problem::TNProblem,
    measure::AbstractMeasure,
    selector::LeastOccurrenceSelector
)
    unfixed_vars = get_unfixed_vars(problem.doms)
    isempty(unfixed_vars) && return Int[]
    least_show_var_idx = argmin(length(problem.static.v2t[u]) for u in unfixed_vars)

    return unfixed_vars[least_show_var_idx]
end

# struct LookAheadSelector <: AbstractSelector
#     max_candidates::Int
#     use_occurrence_prefilter::Bool
# end

# # Default constructor: evaluate up to 10 candidates, with occurrence prefiltering
# LookAheadSelector() = LookAheadSelector(10, true)
# LookAheadSelector(max_candidates::Int) = LookAheadSelector(max_candidates, true)

# function OptimalBranchingCore.select_variables(
#     problem::TNProblem,
#     measure::AbstractMeasure,
#     selector::LookAheadSelector
# )
#     unfixed_vars = get_unfixed_vars(problem.doms)
#     isempty(unfixed_vars) && return Int[]

#     # Determine candidate variables to evaluate
#     candidates = if selector.use_occurrence_prefilter && length(unfixed_vars) > selector.max_candidates
#         # Prefilter: select variables with highest occurrence (most constrained)
#         # This is a heuristic to avoid evaluating all variables
#         sorted_by_occurrence = sort(unfixed_vars,
#                                    by=v -> length(problem.static.v2t[v]),
#                                    rev=true)
#         sorted_by_occurrence[1:min(selector.max_candidates, length(sorted_by_occurrence))]
#     else
#         unfixed_vars
#     end

#     # Evaluate each candidate using look-ahead
#     best_var = candidates[1]
#     best_score = -1.0

#     for var in candidates
#         score = look_ahead_score(problem, var)
#         if score > best_score
#             best_score = score
#             best_var = var
#         end
#     end

#     return best_var
# end

# """
#     HybridSelector <: AbstractSelector

# A hybrid selector that combines occurrence-based and look-ahead selection.

# Fields:
# - `occurrence_weight::Float64` - Weight for occurrence-based score (default: 0.3)
# - `lookahead_weight::Float64` - Weight for look-ahead score (default: 0.7)
# - `max_candidates::Int` - Maximum candidates to evaluate (default: 10)

# This selector balances between the cheap occurrence heuristic and the expensive
# but more accurate look-ahead evaluation.
# """
# struct HybridSelector <: AbstractSelector
#     occurrence_weight::Float64
#     lookahead_weight::Float64
#     max_candidates::Int
# end

# HybridSelector() = HybridSelector(0.3, 0.7, 10)

# function OptimalBranchingCore.select_variables(
#     problem::TNProblem,
#     measure::AbstractMeasure,
#     selector::HybridSelector
# )
#     unfixed_vars = get_unfixed_vars(problem.doms)
#     isempty(unfixed_vars) && return Int[]

#     # If very few variables, just use look-ahead
#     if length(unfixed_vars) <= 3
#         return OptimalBranchingCore.select_variables(problem, measure,
#                                                      LookAheadSelector(length(unfixed_vars), false))
#     end

#     # Get top candidates by occurrence
#     candidates = if length(unfixed_vars) > selector.max_candidates
#         sorted_by_occurrence = sort(unfixed_vars,
#                                    by=v -> length(problem.static.v2t[v]),
#                                    rev=true)
#         sorted_by_occurrence[1:selector.max_candidates]
#     else
#         unfixed_vars
#     end

#     # Normalize occurrence scores to [0, 1]
#     occurrence_counts = [length(problem.static.v2t[v]) for v in candidates]
#     max_occ = maximum(occurrence_counts)
#     min_occ = minimum(occurrence_counts)
#     occurrence_scores = if max_occ > min_occ
#         [(occ - min_occ) / (max_occ - min_occ) for occ in occurrence_counts]
#     else
#         ones(Float64, length(candidates))
#     end

#     # Compute look-ahead scores
#     lookahead_scores = [look_ahead_score(problem, v) for v in candidates]

#     # Normalize look-ahead scores to [0, 1]
#     max_la = maximum(lookahead_scores)
#     min_la = minimum(lookahead_scores)
#     normalized_la = if max_la > min_la
#         [(s - min_la) / (max_la - min_la) for s in lookahead_scores]
#     else
#         ones(Float64, length(candidates))
#     end

#     # Combine scores
#     combined_scores = [selector.occurrence_weight * occurrence_scores[i] +
#                       selector.lookahead_weight * normalized_la[i]
#                       for i in 1:length(candidates)]

#     # Select best
#     best_idx = argmax(combined_scores)
#     return candidates[best_idx]
# end

"""
    RegionQualityMetrics

Metrics for evaluating the quality of a region for branching.

Fields:
- `n_branches::Int` - Number of branches (clauses) in the branching table
- `n_region_vars::Int` - Total variables in the region (boundary + inner)
- `n_boundary_vars::Int` - Number of boundary variables
- `n_inner_vars::Int` - Number of inner variables
- `n_tensors::Int` - Number of tensors in the region
- `avg_config_size::Float64` - Average number of configs per branch
- `branching_factor::Float64` - Estimated branching factor
"""
struct RegionQualityMetrics
    n_branches::Int
    n_region_vars::Int
    n_boundary_vars::Int
    n_inner_vars::Int
    n_tensors::Int
    avg_config_size::Float64
    branching_factor::Float64
end

"""
    evaluate_region_quality(problem::TNProblem, region::Region, table::BranchingTable) -> RegionQualityMetrics

Evaluate the quality of a region and its branching table for variable selection.
"""
function evaluate_region_quality(problem::TNProblem, region::Region, table::BranchingTable)
    n_branches = length(table.table)
    n_region_vars = length(region.boundary_vars) + length(region.inner_vars)
    n_boundary_vars = length(region.boundary_vars)
    n_inner_vars = length(region.inner_vars)
    n_tensors = length(region.tensors)

    # Calculate average config size per branch
    total_configs = sum(length(configs) for configs in table.table)
    avg_config_size = n_branches > 0 ? total_configs / n_branches : 0.0

    # Estimate branching factor
    branching_factor = Float64(n_branches)

    return RegionQualityMetrics(
        n_branches,
        n_region_vars,
        n_boundary_vars,
        n_inner_vars,
        n_tensors,
        avg_config_size,
        branching_factor
    )
end

"""
    score_region_quality(metrics::RegionQualityMetrics) -> Float64

Score a region based on its quality metrics. Lower scores are better.

The scoring considers:
- Fewer branches is better (reduces search tree size)
- Smaller regions are better (less overhead per branch)
- Balanced boundary/inner ratio is preferred
"""
function score_region_quality(metrics::RegionQualityMetrics)
    # Primary goal: minimize branching factor
    branching_penalty = Float64(metrics.n_branches)

    # Secondary: prefer compact regions (fewer variables means less work per branch)
    region_size_penalty = 0.1 * Float64(metrics.n_region_vars)

    # Tertiary: penalize very large average config sizes (indicates complex branches)
    config_penalty = 0.01 * metrics.avg_config_size

    # Lower score is better
    return branching_penalty + region_size_penalty + config_penalty
end

"""
    RegionAwareSelector <: AbstractSelector

Variable selector that evaluates candidate regions and chooses the variable
that produces the best branching structure.

Fields:
- `max_candidates::Int` - Maximum number of candidate variables to evaluate (default: 5)
- `k::Int` - K-hop for region construction (default: 1)
- `max_tensors::Int` - Maximum tensors in region (default: 2)
- `use_occurrence_prefilter::Bool` - Whether to prefilter by occurrence (default: true)

This selector actually constructs the branching tables for candidate variables
and selects based on the quality of the resulting branching structure.
"""
struct RegionAwareSelector <: AbstractSelector
    max_candidates::Int
    k::Int
    max_tensors::Int
    use_occurrence_prefilter::Bool
end

RegionAwareSelector() = RegionAwareSelector(5, 1, 2, true)
RegionAwareSelector(max_candidates::Int) = RegionAwareSelector(max_candidates, 1, 2, true)

function OptimalBranchingCore.select_variables(
    problem::TNProblem,
    measure::AbstractMeasure,
    selector::RegionAwareSelector
)
    unfixed_vars = get_unfixed_vars(problem.doms)
    isempty(unfixed_vars) && return Int[]

    # Determine candidate variables to evaluate
    candidates = if selector.use_occurrence_prefilter && length(unfixed_vars) > selector.max_candidates
        # Prefilter: select variables with highest occurrence (most constrained)
        sorted_by_occurrence = sort(unfixed_vars,
                                   by=v -> length(problem.static.v2t[v]),
                                   rev=true)
        sorted_by_occurrence[1:min(selector.max_candidates, length(sorted_by_occurrence))]
    else
        # If few variables, evaluate all
        if length(unfixed_vars) <= selector.max_candidates
            unfixed_vars
        else
            # Take first max_candidates (already sorted by occurrence or random order)
            unfixed_vars[1:selector.max_candidates]
        end
    end

    # Evaluate each candidate by building its region and branching table
    best_var = candidates[1]
    best_score = Inf

    table_solver = TNContractionSolver(selector.k, selector.max_tensors)

    for var in candidates
        # Build region and branching table for this variable
        region = create_region(problem, var, table_solver)
        table, _ = OptimalBranchingCore.branching_table(problem, table_solver, var)

        # Skip if table is empty (would lead to UNSAT)
        isempty(table.table) && continue

        # Evaluate region quality
        metrics = evaluate_region_quality(problem, region, table)
        score = score_region_quality(metrics)

        if score < best_score
            best_score = score
            best_var = var
        end
    end

    return best_var
end

# """
#     RegionLookaheadSelector <: AbstractSelector

# Hybrid selector combining region quality evaluation with look-ahead propagation.

# Fields:
# - `max_candidates::Int` - Maximum candidates to evaluate (default: 5)
# - `k::Int` - K-hop for region construction (default: 1)
# - `max_tensors::Int` - Maximum tensors in region (default: 2)
# - `region_weight::Float64` - Weight for region quality score (default: 0.6)
# - `lookahead_weight::Float64` - Weight for look-ahead score (default: 0.4)

# This selector combines the structural information from region analysis with
# the propagation information from look-ahead.
# """
# struct RegionLookaheadSelector <: AbstractSelector
#     max_candidates::Int
#     k::Int
#     max_tensors::Int
#     region_weight::Float64
#     lookahead_weight::Float64
# end

# RegionLookaheadSelector() = RegionLookaheadSelector(5, 1, 2, 0.6, 0.4)

# function OptimalBranchingCore.select_variables(
#     problem::TNProblem,
#     measure::AbstractMeasure,
#     selector::RegionLookaheadSelector
# )
#     unfixed_vars = get_unfixed_vars(problem.doms)
#     isempty(unfixed_vars) && return Int[]

#     # Select candidates
#     candidates = if length(unfixed_vars) > selector.max_candidates
#         sorted_by_occurrence = sort(unfixed_vars,
#                                    by=v -> length(problem.static.v2t[v]),
#                                    rev=true)
#         sorted_by_occurrence[1:selector.max_candidates]
#     else
#         unfixed_vars
#     end

#     # Compute both region scores and look-ahead scores
#     region_scores = Float64[]
#     lookahead_scores = Float64[]
#     valid_candidates = Int[]

#     table_solver = TNContractionSolver(selector.k, selector.max_tensors)

#     for var in candidates
#         # Region quality
#         region = create_region(problem, var, table_solver)
#         table, _ = OptimalBranchingCore.branching_table(problem, table_solver, var)

#         # Skip if table is empty
#         isempty(table.table) && continue

#         metrics = evaluate_region_quality(problem, region, table)
#         region_score = score_region_quality(metrics)

#         # Look-ahead score
#         la_score = look_ahead_score(problem, var)

#         push!(region_scores, region_score)
#         push!(lookahead_scores, la_score)
#         push!(valid_candidates, var)
#     end

#     isempty(valid_candidates) && return candidates[1]

#     # Normalize region scores (lower is better, so invert)
#     max_rs = maximum(region_scores)
#     min_rs = minimum(region_scores)
#     normalized_region = if max_rs > min_rs
#         [1.0 - (s - min_rs) / (max_rs - min_rs) for s in region_scores]
#     else
#         ones(Float64, length(region_scores))
#     end

#     # Normalize look-ahead scores (higher is better)
#     max_la = maximum(lookahead_scores)
#     min_la = minimum(lookahead_scores)
#     normalized_lookahead = if max_la > min_la
#         [(s - min_la) / (max_la - min_la) for s in lookahead_scores]
#     else
#         ones(Float64, length(lookahead_scores))
#     end

#     # Combine scores
#     combined_scores = [selector.region_weight * normalized_region[i] +
#                       selector.lookahead_weight * normalized_lookahead[i]
#                       for i in 1:length(valid_candidates)]

#     # Select best
#     best_idx = argmax(combined_scores)
#     return valid_candidates[best_idx]
# end

