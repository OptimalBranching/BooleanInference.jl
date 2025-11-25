function create_region(problem::TNProblem, variable::Int, selector::AbstractSelector)
    return k_neighboring(problem.static, problem.doms, variable; max_tensors = selector.max_tensors, k = selector.k)
end

struct MostOccurrenceSelector <: AbstractSelector 
    k::Int
    max_tensors::Int
end

function compute_var_cover_scores_weighted(problem::TNProblem)
    num_vars = length(problem.static.vars)
    scores = zeros(Float64, num_vars)

    active_tensors = get_active_tensors(problem.static, problem.doms)
    degrees = zeros(Int, length(problem.static.tensors))

    @inbounds for tensor_id in active_tensors
        vars = problem.static.tensors[tensor_id].var_axes
        degree = 0
        @inbounds for var in vars
            !is_fixed(problem.doms[var]) && (degree += 1)
        end
        degrees[tensor_id] = degree
    end

    @inbounds for v in 1:num_vars
        is_fixed(problem.doms[v]) && continue
        for t in problem.static.v2t[v]
            deg = degrees[t]
            if deg > 2
                scores[v] += (deg - 2) / deg
            end
        end
    end
    return scores
end
function findbest(cache::RegionCache, problem::TNProblem{INT}, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, ::MostOccurrenceSelector) where {INT}
    var_scores = compute_var_cover_scores_weighted(problem)
    var_id = argmax(var_scores)
    reset_propagated_cache!(problem)
    result = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return []
    clauses = OptimalBranchingCore.get_clauses(result)
    @assert haskey(problem.propagated_cache, clauses[1])
    return [problem.propagated_cache[clauses[i]] for i in 1:length(clauses)]
end

struct MinGammaSelector <: AbstractSelector
    k::Int
    max_tensors::Int
    table_solver::AbstractTableSolver
    set_cover_solver::AbstractSetCoverSolver
end

function findbest(cache::RegionCache, problem::TNProblem{INT}, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, ::MinGammaSelector) where {INT}
    best_subproblem = nothing
    best_gamma = Inf

    # Check all unfixed variables
    unfixed_vars = get_unfixed_vars(problem)
    @inbounds for var_id in unfixed_vars
        reset_propagated_cache!(problem)
        result = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
        isnothing(result) && continue

        if result.γ < best_gamma
            best_gamma = result.γ
            clauses = OptimalBranchingCore.get_clauses(result)

            @assert haskey(problem.propagated_cache, clauses[1])
            best_subproblem = [problem.propagated_cache[clauses[i]] for i in 1:length(clauses)]

            fixed_indices = findall(iszero, count_unfixed.(best_subproblem))
            !isempty(fixed_indices) && (best_subproblem = [best_subproblem[fixed_indices[1]]])

            best_gamma == 1.0 && break
        end
    end
    # println("best_γ: $best_gamma")
    best_gamma === Inf && return []    
    return best_subproblem
end