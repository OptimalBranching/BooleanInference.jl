struct RegionCache
    var_to_region::Vector{Region}  # Fixed at initialization: var_to_region[var_id] gives the region for variable var_id
    var_to_configs::Vector{Vector{UInt64}}  # Cached full configs from initial contraction for each variable's region
end

function init_cache(problem::TNProblem{INT}, table_solver::AbstractTableSolver, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver, selector::AbstractSelector) where {INT}
    num_vars = length(problem.static.vars)
    unfixed_vars = get_unfixed_vars(problem)

    var_to_region = Vector{Region}(undef, num_vars)
    var_to_configs = Vector{Vector{UInt64}}(undef, num_vars)
    fill!(var_to_configs, Vector{UInt64}())

    # For each unfixed variable, create region and cache full contraction configs
    @inbounds for var_id in unfixed_vars
        region = create_region(problem, var_id, selector)
        var_to_region[var_id] = region

        # Compute full branching table with initial doms (all variables unfixed)
        contracted_tensor, _ = contract_region(problem.static, region, problem.doms)
        configs = map(packint, findall(isone, contracted_tensor))
        var_to_configs[var_id] = configs
    end

    return RegionCache(var_to_region, var_to_configs)
end

