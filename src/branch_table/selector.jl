function create_region(problem::TNProblem, variable::Int, selector::AbstractSelector)
    return k_neighboring(problem.static, problem.doms, variable; max_tensors = selector.max_tensors, k = selector.k)
end

struct MostOccurrenceSelector <: AbstractSelector 
    k::Int
    max_tensors::Int
end
function compute_var_cover_scores_weighted(problem::TNProblem)
    scores = problem.buffer.activity_scores
    fill!(scores, 0.0)

    active_tensors = get_active_tensors(problem.static, problem.doms)

    # Compute scores by directly iterating active tensors and their variables
    @inbounds for tensor_id in active_tensors
        vars = problem.static.tensors[tensor_id].var_axes
        degree = 0

        @inbounds for var in vars
            !is_fixed(problem.doms[var]) && (degree += 1)
        end
    
        if degree > 2
            weight = 100.0 / degree 
            
            @inbounds for var in vars
                if !is_fixed(problem.doms[var])
                    scores[var] += weight
                end
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
        if var_scores[i] > max_score
            max_score = var_scores[i]
            var_id = i
        end
    end
    # Check if all scores are zero - problem has reduced to 2-SAT
    if max_score == 0.0
        @info "2-SAT detected"
        solution = solve_2sat(problem)
        return isnothing(solution) ? nothing : [solution]
    end

    result = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing
    region, _ = get_region_data!(cache, problem, var_id)
    return (OptimalBranchingCore.get_clauses(result), region.vars)
end

struct MinGammaSelector <: AbstractSelector
    k::Int
    max_tensors::Int
    table_solver::AbstractTableSolver
    set_cover_solver::AbstractSetCoverSolver
end
function findbest(cache::RegionCache, problem::TNProblem, m::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, ::MinGammaSelector)
    best_γ = Inf
    best_clauses = nothing
    best_var_id = 0

    # Check all unfixed variables
    unfixed_vars = get_unfixed_vars(problem)
    if length(unfixed_vars) != 0 && measure(problem, NumHardTensors()) == 0
        solution = solve_2sat(problem)
        return isnothing(solution) ? nothing : [solution]
    end
    @inbounds for var_id in unfixed_vars
        reset_propagated_cache!(problem)
        result = compute_branching_result(cache, problem, var_id, m, set_cover_solver)
        isnothing(result) && continue

        if result.γ < best_γ
            best_γ = result.γ
            best_clauses = OptimalBranchingCore.get_clauses(result)
            best_var_id = var_id
            best_γ == 1.0 && break
        end
    end
    best_γ === Inf && return nothing
    region, _ = get_region_data!(cache, problem, best_var_id)
    return (best_clauses, region.vars)
end