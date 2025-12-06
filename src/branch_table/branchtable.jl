struct TNContractionSolver <: AbstractTableSolver end

# Filter cached configs based on current doms and compute branching result for a specific variable
function compute_branching_result(cache::RegionCache, problem::TNProblem{INT}, var_id::Int, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver) where {INT}
    region = cache.var_to_region[var_id]
    cached_configs = cache.var_to_configs[var_id]

    # Filter configs that are compatible with current doms
    feasible_configs = filter_feasible_configs(problem, region, cached_configs)
    isempty(feasible_configs) && return nothing

    # Build branching table from filtered configs
    table = BranchingTable(length(region.vars), [[c] for c in feasible_configs])
    # Compute optimal branching rule
    result = OptimalBranchingCore.optimal_branching_rule(table, region.vars, problem, measure, set_cover_solver)
    return result
end

# Filter configs to only those compatible with current variable domains
function filter_feasible_configs(problem::TNProblem, region::Region, configs::Vector{UInt64})
    feasible = UInt64[]
    mask, value = is_legal(problem.doms[region.vars])
    clause_mask = (UInt64(1) << length(region.vars)) - 1
    @inbounds for config in configs
        (config & mask) == value || continue
        doms = copy(problem.doms)
        changed_indices = Int[]
        @inbounds for (bit_idx, var_id) in enumerate(region.vars)
            doms[var_id] = (config >> (bit_idx - 1)) & 1 == 1 ? DM_1 : DM_0
            push!(changed_indices, var_id)
        end
        touched_tensors = unique(vcat([problem.static.v2t[v] for v in changed_indices]...))
        propagated_doms, _ = propagate(problem.static, doms, touched_tensors)
        problem.propagated_cache[Clause(clause_mask, config)] = propagated_doms
        !has_contradiction(propagated_doms) && push!(feasible, config)
    end
    return feasible
end

