struct MostOccurrenceSelector <: AbstractSelector
    k::Int
    max_tensors::Int
end

"""
Compute variable selection scores based on weighted occurrence in high-degree tensors.

Score(var) = Σ (degree - 2) for all tensors containing var with degree > 2

This simple heuristic has been empirically validated to work well.
"""
function compute_var_cover_scores_weighted(problem::TNProblem)
    scores = problem.buffer.connection_scores
    fill!(scores, 0.0)

    active_tensors = get_active_tensors(problem.static, problem.doms)

    # Compute scores by directly iterating active tensors and their variables
    @inbounds for tensor_id in active_tensors
        vars = problem.static.tensors[tensor_id].var_axes

        # Count unfixed variables in this tensor
        degree = 0
        @inbounds for var in vars
            !is_fixed(problem.doms[var]) && (degree += 1)
        end

        # Only contribute to scores if degree > 2
        if degree > 2
            weight = degree
            @inbounds for var in vars
                !is_fixed(problem.doms[var]) && (scores[var] += weight)
            end
        end
    end
    return scores
end

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, ::MostOccurrenceSelector)
    var_scores = compute_var_cover_scores_weighted(problem)
    # Find maximum and its index in a single pass
    max_score = 0.0
    var_id = 0
    @inbounds for i in eachindex(var_scores)
        is_fixed(problem.doms[i]) && continue
        if var_scores[i] > max_score
            max_score = var_scores[i]
            var_id = i
        end
    end

    result, variables, region = compute_branching_result_with_region(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing, variables
    return (OptimalBranchingCore.get_clauses(result), variables)
end

# Version that also returns the region for logging purposes
function findbest_with_region(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::MostOccurrenceSelector, depth::Int=0)
    var_scores = compute_var_cover_scores_weighted(problem)
    # Find maximum and its index in a single pass
    max_score = 0.0
    var_id = 0
    @inbounds for i in eachindex(var_scores)
        is_fixed(problem.doms[i]) && continue
        if var_scores[i] > max_score
            max_score = var_scores[i]
            var_id = i
        end
    end

    result, variables, region, support_size = compute_branching_result_with_region(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing, variables, region, support_size

    # Get clauses and their size reductions
    clauses = OptimalBranchingCore.get_clauses(result)
    size_reductions = result.branching_vector

    # Sort clauses by size_reduction in descending order (largest reduction first)
    if length(clauses) > 1
        perm = sortperm(size_reductions, rev=true)
        clauses = clauses[perm]
    end

    return (clauses, variables, region, support_size)
end



"""
    MinGammaSelector

A selector that scans ALL unfixed variables to find the one with the minimum
branching factor (γ). This yields the optimal search tree size but is 
computationally expensive (O(num_vars) branching table computations per node).

Best suited for small-scale problems where minimizing search tree depth is 
more important than per-node overhead.
"""
struct MinGammaSelector <: AbstractSelector
    k::Int
    max_tensors::Int
end

function findbest_with_region(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::MinGammaSelector, depth::Int=0)
    best_γ = Inf
    best_result = nothing
    best_variables = Int[]
    best_region = nothing
    best_support_size = 0

    unfixed_vars = get_unfixed_vars(problem)
    isempty(unfixed_vars) && return nothing, Int[], Region(0, Int[], Int[]), 0

    @inbounds for var_id in unfixed_vars
        result, variables, region, support_size = compute_branching_result_with_region(cache, problem, var_id, measure, set_cover_solver)
        isnothing(result) && continue

        if result.γ < best_γ
            best_γ = result.γ
            best_result = result
            best_variables = variables
            best_region = region
            best_support_size = support_size
            # Early exit: γ=1.0 means a single branch (forced assignment)
            best_γ == 1.0 && break
        end
    end

    isnothing(best_result) && return nothing, Int[], Region(0, Int[], Int[]), 0

    # Get clauses and sort by size_reduction descending
    clauses = OptimalBranchingCore.get_clauses(best_result)
    size_reductions = best_result.branching_vector
    if length(clauses) > 1
        perm = sortperm(size_reductions, rev=true)
        clauses = clauses[perm]
    end

    return (clauses, best_variables, best_region, best_support_size)
end


function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::MinGammaSelector)
    result, variables, _, _ = findbest_with_region(cache, problem, measure, set_cover_solver, selector)
    return result, variables
end



"""
    DPLLSelector

Standard DPLL-style branching: selects the highest-connectivity variable (same as 
MostOccurrenceSelector) but uses simple 0/1 branching instead of OptimalBranching.

This serves as a baseline to isolate the contribution of OptimalBranching.
- MostOccurrenceSelector: MostOcc variable selection + OB branching
- DPLLSelector: MostOcc variable selection + Standard 0/1 branching
"""
struct DPLLSelector <: AbstractSelector end

function findbest_with_region(cache::RegionCache, problem::TNProblem, ::AbstractMeasure, ::AbstractSetCoverSolver, ::DPLLSelector, depth::Int=0)
    var_scores = compute_var_cover_scores_weighted(problem)
    # Find maximum connectivity variable (SAME as MostOccurrenceSelector)
    max_score = 0.0
    var_id = 0
    @inbounds for i in eachindex(var_scores)
        is_fixed(problem.doms[i]) && continue
        if var_scores[i] > max_score
            max_score = var_scores[i]
            var_id = i
        end
    end

    if var_id == 0
        return nothing, Int[], Region(0, Int[], Int[]), 0
    end

    # STANDARD BRANCHING: just x=0 and x=1, no OB optimization
    clause_false = Clause(UInt64(1), UInt64(0))  # var=false
    clause_true = Clause(UInt64(1), UInt64(1))   # var=true
    clauses = [clause_false, clause_true]
    variables = [var_id]

    dummy_region = Region(var_id, Int[], [var_id])
    support_size = 2

    return (clauses, variables, dummy_region, support_size)
end

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::DPLLSelector)
    result, variables, _, _ = findbest_with_region(cache, problem, measure, set_cover_solver, selector)
    return result, variables
end
