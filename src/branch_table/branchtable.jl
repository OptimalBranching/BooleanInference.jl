struct TNContractionSolver <: AbstractTableSolver end

# Filter cached configs based on current doms and compute branching result for a specific variable
function compute_branching_result(cache::RegionCache, problem::TNProblem, var_id::Int, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver)
    region, cached_configs = get_region_data!(cache, problem, var_id)

    # Filter configs that are compatible with current doms
    feasible_configs = filter_feasible_configs(problem, region, cached_configs, measure)
    isempty(feasible_configs) && return nothing, region.vars

    # Drop variables that are already fixed to avoid no-op branching
    unfixed_positions = Int[]
    unfixed_vars = Int[]
    @inbounds for (i, v) in enumerate(region.vars)
        if !is_fixed(problem.doms[v])
            push!(unfixed_positions, i)
            push!(unfixed_vars, v)
        end
    end
    isempty(unfixed_vars) && return nothing, region.vars

    # Project configs onto unfixed variables only
    projected = UInt64[]
    @inbounds for config in feasible_configs
        new_config = UInt64(0)
        for (new_i, old_i) in enumerate(unfixed_positions)
            if (config >> (old_i - 1)) & 1 == 1
                new_config |= UInt64(1) << (new_i - 1)
            end
        end
        push!(projected, new_config)
    end
    unique!(projected)

    # Build branching table from filtered configs
    table = BranchingTable(length(unfixed_vars), [[c] for c in projected])
    # Compute optimal branching rule
    result = OptimalBranchingCore.optimal_branching_rule(table, unfixed_vars, problem, measure, set_cover_solver)
    return result, unfixed_vars
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

function probe_config!(buffer::SolverBuffer, problem::TNProblem, vars::Vector{Int}, config::UInt64, measure::AbstractMeasure)
    # All variables in config are being set, so mask = all 1s
    mask = (UInt64(1) << length(vars)) - 1
    
    scratch = probe_assignment_core!(problem, buffer, problem.doms, vars, mask, config)
    is_feasible = scratch[1] != DM_NONE
    is_feasible && (buffer.branching_cache[Clause(mask, config)] = measure_core(problem.static, scratch, measure))
    return is_feasible
end
