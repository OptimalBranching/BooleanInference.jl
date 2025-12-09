struct TNContractionSolver <: AbstractTableSolver end

# Filter cached configs based on current doms and compute branching result for a specific variable
function compute_branching_result(cache::RegionCache, problem::TNProblem, var_id::Int, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver)
    region, cached_configs = get_region_data!(cache, problem, var_id)

    # Filter configs that are compatible with current doms
    feasible_configs = filter_feasible_configs(problem, region, cached_configs, measure)
    isempty(feasible_configs) && return nothing

    # Build branching table from filtered configs
    table = BranchingTable(length(region.vars), [[c] for c in feasible_configs])
    # Compute optimal branching rule
    result = OptimalBranchingCore.optimal_branching_rule(table, region.vars, problem, measure, set_cover_solver)
    return result
end


@inline function probe_config!(buffer::SolverBuffer, problem::TNProblem, vars::Vector{Int}, config::UInt64, measure::AbstractMeasure)
    # All variables in config are being set, so mask = all 1s
    mask = (UInt64(1) << length(vars)) - 1
    @assert !(buffer.scratch_doms === problem.doms) "buffer.scratch_doms and problem.doms are the same object!"
    scratch = probe_assignment_core!(problem.static, buffer, problem.doms, vars, mask, config)
    @assert scratch === buffer.scratch_doms "scratch should be buffer.scratch_doms"
    @assert !(scratch === problem.doms) "scratch should not be problem.doms"
    if scratch[1] != DM_NONE
        buffer.branching_cache[Clause(mask, config)] = measure_core(problem.static, scratch, measure)
        return true
    end
    return false
end

@inline function get_region_masks(doms::Vector{DomainMask}, vars::Vector{Int})
    return mask_value(doms, vars, UInt64)
end

function filter_feasible_configs(problem::TNProblem, region::Region, configs::Vector{UInt64}, measure::AbstractMeasure)
    feasible = UInt64[]
    check_mask, check_value = get_region_masks(problem.doms, region.vars)

    buffer = problem.buffer
    @inbounds for config in configs
        (config & check_mask) == check_value || continue
        is_feasible = probe_config!(buffer, problem, region.vars, config, measure)
        is_feasible && push!(feasible, config)
    end
    return feasible
end
