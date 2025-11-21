struct TNProblem <: AbstractProblem
    static::BipartiteGraph
    doms::Vector{DomainMask}
    n_unfixed::Int
    stats::BranchingStats
    propagated_cache::Dict{Clause{UInt64}, Vector{DomainMask}}

    function TNProblem(static::BipartiteGraph, doms::Vector{DomainMask}, stats::BranchingStats=BranchingStats(), propagated_cache::Dict{Clause{UInt64}, Vector{DomainMask}}=Dict{Clause{UInt64}, Vector{DomainMask}}())
        n_unfixed = count_unfixed(doms)
        new(static, doms, n_unfixed, stats, propagated_cache)
    end
end

function TNProblem(static::BipartiteGraph)
    doms = propagate(static, init_doms(static))
    return TNProblem(static, doms)
end

function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(problem.n_unfixed)/$(length(problem.static.vars)))")
end

get_var_value(problem::TNProblem, var_id::Int) = get_var_value(problem.doms, var_id)
get_var_value(problem::TNProblem, var_ids::Vector{Int}) = Bool[get_var_value(problem.doms, var_id) for var_id in var_ids]

is_solved(problem::TNProblem) = problem.n_unfixed == 0

get_branching_stats(problem::TNProblem) = copy(problem.stats)

reset_branching_stats!(problem::TNProblem) = reset!(problem.stats)
