struct Region
    id::Int
    tensors::Vector{Int}
    vars::Vector{Int}
end

function Base.show(io::IO, region::Region)
    print(io, "Region(focus=$(region.id), tensors=$(region.tensors), vars=$(region.vars))")
end

function Base.copy(region::Region)
    return Region(region.id, region.tensors, region.vars)
end

struct RegionCache{S}
    selector::S
    initial_doms::Vector{DomainMask}
    var_to_region::Vector{Union{Region, Nothing}}  # Fixed at initialization: var_to_region[var_id] gives the region for variable var_id
    var_to_configs::Vector{Union{Vector{UInt64}, Nothing}}  # Cached full configs from initial contraction for each variable's region
end

function init_cache(problem::TNProblem, table_solver::AbstractTableSolver, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::AbstractSelector)
    num_vars = length(problem.static.vars)
    
    var_to_region = Vector{Union{Region, Nothing}}(nothing, num_vars)
    var_to_configs = Vector{Union{Vector{UInt64}, Nothing}}(nothing, num_vars)

    return RegionCache(selector, copy(problem.doms), var_to_region, var_to_configs)
end

function get_region_data!(cache::RegionCache, problem::TNProblem, var_id::Int)
    if isnothing(cache.var_to_region[var_id])
        region = create_region(problem.static, cache.initial_doms, var_id, cache.selector)
        cache.var_to_region[var_id] = region

        # Compute full branching table with initial doms
        contracted_tensor, _ = contract_region(problem.static, region, cache.initial_doms)
        configs = map(packint, findall(isone, contracted_tensor))
        cache.var_to_configs[var_id] = configs
    end
    return cache.var_to_region[var_id], cache.var_to_configs[var_id]
end
