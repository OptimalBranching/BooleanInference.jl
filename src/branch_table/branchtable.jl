struct TNContractionSolver <: AbstractTableSolver end

function branching_table!(problem::TNProblem, ::TNContractionSolver, region::Region; cache::Bool=true)
    contracted_tensor, output_var_ids = contract_region(problem.static, region, problem.doms)
    # Scan the contracted tensor: every entry equal to one(Tropical)
    configs = map(packint, findall(isone, contracted_tensor))
    # propagate the configurations to get the feasible solutions
    feasible_configs = collect_feasible!(problem, region, configs; cache)
    table = BranchingTable(length(output_var_ids), [[c] for c in feasible_configs])
    return table, output_var_ids
end

packint(bits::NTuple{N, Int}) where {N} = reduce(|, (UInt64(b) << (i - 1) for (i, b) in enumerate(bits)); init = UInt64(0))
packint(i::Int) = packint((i - 1,))
packint(ci::CartesianIndex{N}) where {N} = packint(ntuple(j -> ci.I[j] - 1, N))

# Apply a clause to domain masks, fixing variables according to the clause's mask and values
function apply_config!(config::UInt64, variables::Vector{Int}, original_doms::Vector{DomainMask})
    changed_indices = Int[]
    @inbounds for (bit_idx, var_id) in enumerate(variables)
        original_doms[var_id] = (config >> (bit_idx - 1)) & 1 == 1 ? DM_1 : DM_0
        push!(changed_indices, var_id)
    end
    return changed_indices
end

function is_feasible_solution(problem::TNProblem, region::Region, config::UInt64)
    doms = copy(problem.doms)
    @assert !has_contradiction(doms) "Domain has contradiction before applying config $config"
    changed_indices = apply_config!(config, vcat(region.boundary_vars, region.inner_vars), doms)
    propagated_doms = propagate(problem.static, doms, changed_indices)
    has_contradiction(propagated_doms) && return false, propagated_doms
    return true, propagated_doms
end

function collect_feasible!(problem::TNProblem, region::Region, configs::Vector{UInt64}; cache::Bool)
    feasible_configs = UInt64[]
    bit_length = UInt64(ndigits(UInt64(configs[end]), base=2))
    @inbounds for config in configs
        feasible, propagated_doms = is_feasible_solution(problem, region, config)
        feasible || continue

        push!(feasible_configs, config)
        cache && (problem.propagated_cache[Clause(bit_length, config)] = propagated_doms)
    end
    return feasible_configs
end

