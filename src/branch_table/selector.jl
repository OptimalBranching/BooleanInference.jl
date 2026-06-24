struct MostOccurrenceSelector <: AbstractSelector 
    k::Int
    max_tensors::Int
end
function compute_var_cover_scores_weighted(problem::TNProblem)
    scores = problem.buffer.connection_scores
    fill!(scores, 0.0)
    # copyto!(scores, problem.buffer.activity_scores)

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
        is_fixed(problem.doms[i]) && continue
        if var_scores[i] > max_score
            max_score = var_scores[i]
            var_id = i
        end
    end
    
    # Find maximum activity score among unfixed variables
    # max_score = -Inf
    # var_id = 0
    # @inbounds for i in eachindex(problem.buffer.activity_scores)
    #     is_fixed(problem.doms[i]) && continue
    #     if problem.buffer.activity_scores[i] > max_score
    #         max_score = problem.buffer.activity_scores[i]
    #         var_id = i
    #     end
    # end
    
    # Check if all scores are zero - problem has reduced to 2-SAT
    # @assert max_score > 0.0 "Max score is zero"

    result, variables = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing, variables
    return (OptimalBranchingCore.get_clauses(result), variables)
end

# Difficulty-guided lookahead selector (selector-design S1/S2).
# Among the top-`pool` candidate vars (by connection score), probe both polarities
# with GAC and pick the var whose HARDER child has the lowest connectivity-weighted
# difficulty (sum of active tensor degrees). Failed literals are taken immediately.
# Cheap (O(pool) propagations/node) and beats MostOccurrence on hard instances.
struct DiffLookaheadSelector <: AbstractSelector
    k::Int
    max_tensors::Int
    pool::Int
end
DiffLookaheadSelector(k::Int, max_tensors::Int) = DiffLookaheadSelector(k, max_tensors, 16)

@inline function _sum_active_degree(static::ConstraintNetwork, doms::Vector{DomainMask})
    s = 0
    @inbounds for t in static.tensors
        for v in t.var_axes
            !is_fixed(doms[v]) && (s += 1)
        end
    end
    return s
end

function findbest(cache::RegionCache, problem::TNProblem, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, sel::DiffLookaheadSelector)
    scores = compute_var_cover_scores_weighted(problem)
    doms = problem.doms
    cands = Int[]
    @inbounds for i in eachindex(scores)
        (is_fixed(doms[i]) || scores[i] <= 0.0) && continue
        push!(cands, i)
    end
    isempty(cands) && return nothing, Int[]
    sort!(cands, by = i -> -scores[i])
    length(cands) > sel.pool && (cands = cands[1:sel.pool])

    buffer = problem.buffer
    best = typemax(Int); var_id = 0
    @inbounds for u in cands
        c0 = probe_assignment_core!(problem, buffer, doms, [u], UInt64(1), UInt64(0))
        f0 = has_contradiction(c0); d0 = f0 ? 0 : _sum_active_degree(problem.static, c0)
        c1 = probe_assignment_core!(problem, buffer, doms, [u], UInt64(1), UInt64(1))
        f1 = has_contradiction(c1); d1 = f1 ? 0 : _sum_active_degree(problem.static, c1)
        if f0 || f1
            var_id = u; break          # failed literal ⇒ forced, take immediately
        end
        s = max(d0, d1)
        s < best && (best = s; var_id = u)
    end
    var_id == 0 && (var_id = cands[1])

    # probing above scribbled in the branching cache via no path that matters, but
    # clear it so compute_branching_result starts clean for the chosen var
    empty!(buffer.branching_cache)
    result, variables = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
    isnothing(result) && return nothing, variables
    return (OptimalBranchingCore.get_clauses(result), variables)
end

# struct MinGammaSelector <: AbstractSelector
#     k::Int
#     max_tensors::Int
#     table_solver::AbstractTableSolver
#     set_cover_solver::AbstractSetCoverSolver
# end
# function findbest(cache::RegionCache, problem::TNProblem, m::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, ::MinGammaSelector)
#     best_γ = Inf
#     best_clauses = nothing
#     best_variables = nothing

#     # Check all unfixed variables
#     unfixed_vars = get_unfixed_vars(problem)
#     if length(unfixed_vars) != 0 && measure(problem, NumHardTensors()) == 0
#         solution = solve_2sat(problem)
#         return isnothing(solution) ? nothing : [solution]
#     end
#     @inbounds for var_id in unfixed_vars
#         reset_propagated_cache!(problem)
#         result, variables = compute_branching_result(cache, problem, var_id, m, set_cover_solver)
#         isnothing(result) && continue

#         if result.γ < best_γ
#             best_γ = result.γ
#             best_clauses = OptimalBranchingCore.get_clauses(result)
#             best_variables = variables
#             best_γ == 1.0 && break
#         end
#     end
#     best_γ === Inf && return nothing
#     return (best_clauses, best_variables)
# end
