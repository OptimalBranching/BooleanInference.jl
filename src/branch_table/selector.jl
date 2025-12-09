function create_region(problem::TNProblem, variable::Int, selector::AbstractSelector)
    return k_neighboring(problem.static, problem.doms, variable; max_tensors = selector.max_tensors, k = selector.k)
end

struct MostOccurrenceSelector <: AbstractSelector 
    k::Int
    max_tensors::Int
end
function compute_var_cover_scores_weighted(problem::TNProblem)
    num_vars = length(problem.static.vars)
    scores = problem.buffer.activity_scores
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
            weight = degree - 2
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
        if var_scores[i] > max_score
            max_score = var_scores[i]
            var_id = i
        end
    end    
    # Check if all scores are zero - problem has reduced to 2-SAT
    if max_score == 0.0
        @info "2-SAT detected"
        solution = solve_2sat(problem)
        return isnothing(solution) ? [] : [solution]
    end

    result = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return []
    clauses = OptimalBranchingCore.get_clauses(result)
    # @assert haskey(problem.buffer.branching_cache, clauses[1])
    return [problem.buffer.branching_cache[clauses[i]] for i in 1:length(clauses)]
end

struct MinGammaSelector <: AbstractSelector
    k::Int
    max_tensors::Int
    table_solver::AbstractTableSolver
    set_cover_solver::AbstractSetCoverSolver
end
function findbest(cache::RegionCache, problem::TNProblem, m::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, ::MinGammaSelector)
    best_subproblem = nothing
    best_γ = Inf

    # Check all unfixed variables
    unfixed_vars = get_unfixed_vars(problem)
    if length(unfixed_vars) != 0 && measure(problem, NumHardTensors()) == 0
        solution = solve_2sat(problem)
        if isnothing(solution)
            return []
        else
            return [solution]
        end
    end
    @inbounds for var_id in unfixed_vars
        reset_propagated_cache!(problem)
        result = compute_branching_result(cache, problem, var_id, m, set_cover_solver)
        isnothing(result) && continue

        if result.γ < best_γ
            best_γ = result.γ
            clauses = OptimalBranchingCore.get_clauses(result)

            @assert haskey(problem.buffer.branching_cache, clauses[1])
            best_subproblem = [problem.buffer.branching_cache[clauses[i]] for i in 1:length(clauses)]

            fixed_indices = findall(iszero, count_unfixed.(best_subproblem))
            !isempty(fixed_indices) && (best_subproblem = [best_subproblem[fixed_indices[1]]])

            best_γ == 1.0 && break
        end
    end
    best_γ === Inf && return []    
    return best_subproblem
end