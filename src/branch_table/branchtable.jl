struct TNContractionSolver <: AbstractTableSolver end

# Filter cached configs based on current doms and compute branching result for a specific variable
function compute_branching_result(cache::RegionCache, problem::TNProblem, var_id::Int, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver)
    region, cached_configs = get_region_data!(cache, problem, var_id)

    # Filter configs that are compatible with current doms
    feasible_configs = filter_feasible_configs(problem, region, cached_configs)
    isempty(feasible_configs) && return nothing

    # Build branching table from filtered configs
    table = BranchingTable(length(region.vars), [[c] for c in feasible_configs])
    # Compute optimal branching rule
    result = OptimalBranchingCore.optimal_branching_rule(table, region.vars, problem, measure, set_cover_solver)
    return result
end


@inline function probe_config!(buffer::SolverBuffer, problem::TNProblem, vars::Vector{Int}, config::UInt64)
    # All variables in config are being set, so mask = all 1s
    mask = (UInt64(1) << length(vars)) - 1
    scratch = probe_assignment_core!(problem.static, buffer, problem.doms, vars, mask, config)
    return scratch[1] != DM_NONE
end

@inline function get_region_masks(doms::Vector{DomainMask}, vars::Vector{Int})
    mask = UInt64(0)
    value = UInt64(0)
    
    @inbounds for (i, var_id) in enumerate(vars)
        d = doms[var_id]
        if d == DM_1
            bit = UInt64(1) << (i - 1)
            mask |= bit
            value |= bit
        elseif d == DM_0
            mask |= (UInt64(1) << (i - 1))
        end
    end
    return mask, value
end

function filter_feasible_configs(problem::TNProblem, region::Region, configs::Vector{UInt64})
    feasible = UInt64[]
    clause_mask = (UInt64(1) << length(region.vars)) - 1

    check_mask, check_value = get_region_masks(problem.doms, region.vars)

    buffer = problem.buffer
    @inbounds for config in configs
        (config & check_mask) == check_value || continue
        is_feasible = probe_config!(buffer, problem, region.vars, config)

        if is_feasible
            push!(feasible, config)
            buffer.branching_cache[Clause(clause_mask, config)] = copy(buffer.scratch_doms)
        end
    end
    return feasible
end
