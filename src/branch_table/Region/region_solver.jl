struct RegionTableSolver <: AbstractTableSolver end


function OptimalBranchingCore.branching_table(problem::TNProblem, ::RegionTableSolver, region::Region)
    stats = problem.ws.branch_stats

    # Check if we have a cached table for this region
    cached_region, cached_table = get_cached_region(region.id)
    if !isnothing(cached_region) && !isnothing(cached_table)
        # Validate that cached region is compatible with current problem
        n_vars = length(problem.doms)
        var_ids = vcat(cached_region.boundary_vars, cached_region.inner_vars)
        is_valid = all(1 <= var_id <= n_vars for var_id in var_ids)

        if is_valid
            record_cache_hit!(stats)
            @debug "RegionTableSolver: Using cached table for region $(region.id)"
            filtered_table, unfixed_vars = filter_branching_table(cached_region, cached_table, problem)
            return filtered_table, unfixed_vars
        end
        # If cached region is invalid, treat as cache miss and recompute
    end

    record_cache_miss!(stats)

    n_boundary = length(region.boundary_vars)
    n_inner = length(region.inner_vars)
    n_total = n_boundary + n_inner

    @debug "RegionTableSolver: Building table for region with $(n_boundary) boundary vars, $(n_inner) inner vars"

    # Contract with all-unfixed doms for consistent caching
    all_unfixed_doms = fill(DM_BOTH, length(problem.doms))

    contraction_start_time = time_ns()

    # Contract the region to get the tensor network result
    contracted_tensor, _ = contract_region(problem.static, region, all_unfixed_doms)

    contraction_time = (time_ns() - contraction_start_time) / 1e9
    record_contraction_time!(stats, contraction_time)

    # Simply find all satisfying configurations directly
    one_tropical = one(Tropical{Float64})
    valid_configs = UInt64[]

    @inbounds for lin in eachindex(contracted_tensor)
        if contracted_tensor[lin] == one_tropical
            # LinearIndices gives 1-based, subtract 1 for 0-based bit representation
            config_bits = UInt64(LinearIndices(contracted_tensor)[lin] - 1)
            push!(valid_configs, config_bits)
        end
    end

    if isempty(valid_configs)
        table = BranchingTable(0, [UInt64[]])
        cache_region!(region, table)
        return table, Int[]
    end

    table = BranchingTable(n_total, [valid_configs])
    cache_region!(region, table)

    @debug "RegionTableSolver: Built table with $(length(valid_configs)) valid configs"

    # Filter the table based on current problem state
    filtered_table, unfixed_vars = filter_branching_table(region, table, problem)
    return filtered_table, unfixed_vars
end
