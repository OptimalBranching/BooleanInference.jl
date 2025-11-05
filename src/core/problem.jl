struct TNProblem <: AbstractProblem
    static::TNStatic
    doms::Vector{DomainMask}
    n_unfixed::Int
    ws::DynamicWorkspace
end

function TNProblem(static::TNStatic; verbose::Bool = false)::TNProblem
    doms = init_doms(static)
    ws = DynamicWorkspace(length(static.vars), verbose)
    doms = propagate(static, doms, collect(1:length(static.vars)), ws)
    n_unfixed = count_unfixed(doms)
    return TNProblem(static, doms, n_unfixed, ws)
end

function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(problem.n_unfixed)/$(length(problem.static.vars)))")
end

get_var_value(problem::TNProblem, var_id::Int) = get_var_value(problem.doms, var_id)
get_var_value(problem::TNProblem, var_ids::Vector{Int}) = Bool[get_var_value(problem.doms, var_id) for var_id in var_ids]

is_solved(problem::TNProblem) = problem.n_unfixed == 0

function cache_branch_solution!(problem::TNProblem)
    ws = problem.ws
    copyto!(ws.cached_doms, problem.doms)
    ws.has_cached_solution = true
    return nothing
end

function reset_last_branch_problem!(problem::TNProblem)
    problem.ws.has_cached_solution = false
    return nothing
end

@inline has_last_branch_problem(problem::TNProblem) = problem.ws.has_cached_solution

function last_branch_problem(problem::TNProblem)
    has_last_branch_problem(problem) || return nothing
    doms = copy(problem.ws.cached_doms)
    fixed = count(x -> is_fixed(x), doms)
    @assert fixed == length(doms)
    return TNProblem(problem.static, doms, 0, problem.ws)
end

function get_branching_stats(problem::TNProblem)
    return copy(problem.ws.branch_stats)
end

function reset_branching_stats!(problem::TNProblem)
    reset!(problem.ws.branch_stats)
    return nothing
end
