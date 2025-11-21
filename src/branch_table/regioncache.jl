# stores a mapping from region (as a vector of variables) to the optimal branching rule for that region
# the first variables is the center variable of the region
struct RegionCache{INT, T}
    data::Dict{Vector{Int}, OptimalBranchingCore.OptimalBranchingResult{INT, T}}
end

Base.empty(::RegionCache{INT, T}) where {INT, T} = RegionCache(Dict{Vector{Int}, OptimalBranchingCore.OptimalBranchingResult{INT, T}}())

function init_cache(problem::TNProblem, table_solver::AbstractTableSolver, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver)
    all_variables = get_unfixed_vars(problem)
    return update!(empty(cache), problem, all_variables, table_solver, measure, set_cover_solver)
end
function update(cache::RegionCache, problem::TNProblem, touched_vars::Vector{Int}, table_solver::AbstractTableSolver, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver)
    keys = [key for key in keys(cache.data) if any(x -> x ∈ touched_vars, key)]
    newcache = deepcopy(cache)
    tag = update!(newcache, problem, keys, table_solver, measure, set_cover_solver)
    return tag, newcache
end

# return a Boolean, if false, means no feasible solutions for this subproblem!!!!
function update!(cache::RegionCache{INT, T}, problem::TNProblem, keys, table_solver::AbstractTableSolver, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver) where {INT, T}
    for key in keys
        tbl, variables = branching_table!(problem, table_solver, key; cache=false)
        isempty(tbl.table) && return false  # no feasible solutions, not considering this variables any more.
        new_result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, measure, set_cover_solver)
        cache.data[key] = new_result
    end
    return true
end

# returns a tuple of (region_vars, result)
function findbest(cache::RegionCache)
    _, idx = findmin(val -> val.γ, cache.data)
    return idx, cache.data[idx]
end