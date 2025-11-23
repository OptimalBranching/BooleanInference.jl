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
    @inbounds for config in configs
        if is_config_compatible(config, region.vars, problem.doms)
            doms = copy(problem.doms)
            changed_indices = Int[]
            for (bit_idx, var_id) in enumerate(region.vars)
                doms[var_id] = (config >> (bit_idx - 1)) & 1 == 1 ? DM_1 : DM_0
                push!(changed_indices, var_id)
            end
            touched_tensors = unique(vcat([problem.static.v2t[v] for v in changed_indices]...))
            propagated_doms, propagated_vars = propagate(problem.static, doms, touched_tensors)
            !has_contradiction(propagated_doms) && push!(feasible, config)
        end
    end
    return feasible
end

# Check if a config is compatible with current domains
function is_config_compatible(config::UInt64, variables::Vector{Int}, doms::Vector{DomainMask})
    @inbounds for (bit_idx, var_id) in enumerate(variables)
        is_fixed(doms[var_id]) || continue

        # Extract the bit value for this variable from config
        config_value = (config >> (bit_idx - 1)) & 1
        required_value = has1(doms[var_id]) ? 1 : 0

        # If config assigns a different value than what's fixed, it's incompatible
        config_value != required_value && return false
    end
    return true
end

# Apply clause assignments to domains
function apply_clause(clause::Clause, variables::Vector{Int}, original_doms::Vector{DomainMask})
    doms = copy(original_doms)
    changed_vars = Int[]

    @inbounds for (var_idx, var_id) in enumerate(variables)
        if ismasked(clause, var_idx)
            new_domain = getbit(clause, var_idx) ? DM_1 : DM_0
            if doms[var_id] != new_domain
                doms[var_id] = new_domain
                push!(changed_vars, var_id)
            end
        end
    end
    return doms, changed_vars
end

# Find the best variable to branch on
function findbest(cache::RegionCache, problem::TNProblem{INT}, measure::AbstractMeasure, set_cover_solver::AbstractSetCoverSolver) where {INT}
    best_subproblem = nothing
    best_gamma = Inf

    # Check all unfixed variables
    unfixed_vars = get_unfixed_vars(problem)
    @inbounds for var_id in unfixed_vars
        reset_propagated_cache!(problem)
        result = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
        isnothing(result) && continue
        # @info "var_id: $var_id, gamma: $(result.γ)"

        if result.γ < best_gamma
            best_gamma = result.γ
            clauses = OptimalBranchingCore.get_clauses(result)
            @assert haskey(problem.propagated_cache, clauses[1])
            best_subproblem = [problem.propagated_cache[clauses[i]] for i in 1:length(clauses)]

            best_gamma == 1.0 && break
        end
    end

    best_gamma === Inf && return []
    return best_subproblem
end
