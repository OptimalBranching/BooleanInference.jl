struct TNContractionSolver <: AbstractTableSolver end

# function branching_table!(problem::TNProblem, ::TNContractionSolver, region::Region; cache::Bool=true)
#     contracted_tensor, output_var_ids = contract_region(problem.static, region, problem.doms)
#     # Scan the contracted tensor: every entry equal to one(Tropical)
#     configs = map(packint, findall(isone, contracted_tensor))
#     # propagate the configurations to get the feasible solutions
#     feasible_configs = collect_feasible!(problem, region, configs; cache)
#     table = BranchingTable(length(output_var_ids), [[c] for c in feasible_configs])
#     return table, output_var_ids
# end

# # Apply a clause to domain masks, fixing variables according to the clause's mask and values
# function apply_config!(config::UInt64, variables::Vector{Int}, original_doms::Vector{DomainMask})
#     changed_indices = Int[]
#     @inbounds for (bit_idx, var_id) in enumerate(variables)
#         original_doms[var_id] = (config >> (bit_idx - 1)) & 1 == 1 ? DM_1 : DM_0
#         push!(changed_indices, var_id)
#     end
#     return changed_indices
# end

# function is_feasible_solution(problem::TNProblem, region::Region, config::UInt64)
#     doms = copy(problem.doms)
#     @assert !has_contradiction(doms) "Domain has contradiction before applying config $config"
#     changed_indices = apply_config!(config, region.vars, doms)
#     propagated_doms, _ = propagate(problem.static, doms, changed_indices)
#     has_contradiction(propagated_doms) && return false, propagated_doms
#     return true, propagated_doms
# end

# function collect_feasible!(problem::TNProblem, region::Region, configs::Vector{UInt64}; cache::Bool)
#     feasible_configs = UInt64[]
#     isempty(configs) && return feasible_configs
#     bit_length = UInt64(ndigits(UInt64(configs[end]), base=2))
#     @inbounds for config in configs
#         feasible, propagated_doms = is_feasible_solution(problem, region, config)
#         feasible || continue

#         push!(feasible_configs, config)
#         cache && (problem.propagated_cache[Clause(bit_length, config)] = propagated_doms)
#     end
#     return feasible_configs
# end

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

