# ============================================================================
# Branching Table Construction
#
# This module handles the construction of branching tables from tensor network
# regions. It computes feasible configurations and applies optimal branching
# rules with a fast-path for gamma=1 detection.
# ============================================================================

"""
    TNContractionSolver <: AbstractTableSolver

Table solver that uses tensor network contraction to enumerate
feasible configurations for a region.
"""
struct TNContractionSolver <: AbstractTableSolver end

# ============================================================================
# Core Branching Functions
# ============================================================================

"""
    compute_branching_result(cache, problem, var_id, measure, solver) -> (result, variables, table_info)

Compute the optimal branching result for a variable's region.
Used during the main branching phase (not reduction).

# Returns
- `result`: OptimalBranchingResult or `nothing` if no valid branching
- `variables`: List of unfixed variables in the region
- `table_info`: NamedTuple (n_configs, n_vars) for overhead analysis
"""
function compute_branching_result(
    cache::RegionCache,
    problem::TNProblem,
    var_id::Int,
    measure::AbstractMeasure,
    set_cover_solver::AbstractSetCoverSolver
)
    projected, unfixed_vars = prepare_branching_configs(cache, problem, var_id, measure)
    isnothing(projected) && return (nothing, unfixed_vars, (n_configs=0, n_vars=length(unfixed_vars)))

    table = BranchingTable(length(unfixed_vars), [[c] for c in projected])
    result = OptimalBranchingCore.optimal_branching_rule(table, unfixed_vars, problem, measure, set_cover_solver)
    return (result, unfixed_vars, (n_configs=length(projected), n_vars=length(unfixed_vars)))
end

"""
    prepare_branching_configs(cache, problem, var_id, measure) -> (configs, variables)

Prepare projected configurations for branching computation.
Filters configs by feasibility and projects onto unfixed variables.
"""
function prepare_branching_configs(cache::RegionCache, problem::TNProblem, var_id::Int, measure::AbstractMeasure)
    region, cached_configs = get_region_data!(cache, problem, var_id)

    feasible_configs = filter_feasible_configs(problem, region, cached_configs, measure)
    isempty(feasible_configs) && return (nothing, region.vars)

    unfixed_positions, unfixed_vars = extract_unfixed_vars(problem.doms, region.vars)
    isempty(unfixed_vars) && return (nothing, region.vars)

    projected = project_configs(feasible_configs, unfixed_positions)
    return (projected, unfixed_vars)
end

# ============================================================================
# Gamma-1 Detection (Forced Variable Detection)
# ============================================================================

"""
    find_forced_assignment(cache, problem, var_id, measure) -> Union{Nothing, Tuple}

Check if a region has a forced variable assignment (gamma=1).
Optimized for the reduction phase with early termination.

# Returns
- `nothing` if no forced assignment exists
- `(clause, variables)` if a forced assignment is found
"""
function find_forced_assignment(
    cache::RegionCache,
    problem::TNProblem,
    var_id::Int,
    measure::AbstractMeasure
)
    region, cached_configs = get_region_data!(cache, problem, var_id)
    
    unfixed_positions, unfixed_vars = extract_unfixed_vars(problem.doms, region.vars)
    isempty(unfixed_vars) && return nothing
    
    result = filter_and_detect_forced(problem, region, cached_configs, unfixed_positions, length(unfixed_vars))
    isnothing(result) && return nothing
    
    return (result, unfixed_vars)
end

"""
    filter_and_detect_forced(problem, region, configs, unfixed_positions, n_unfixed) -> Union{Nothing, Clause}

Combined filtering + forced variable detection with early termination.
Faster than separate filter + detect because:
1. Tracks OR/AND aggregates incrementally during filtering
2. Stops as soon as no forced variable is possible
3. No intermediate vector allocation
"""
function filter_and_detect_forced(
    problem::TNProblem, 
    region::Region, 
    configs::Vector{UInt64}, 
    unfixed_positions::Vector{Int},
    n_unfixed::Int
)
    check_mask, check_value = get_region_masks(problem.doms, region.vars)
    var_mask = (UInt64(1) << n_unfixed) - 1
    
    or_all = UInt64(0)
    and_all = ~UInt64(0)
    found_any = false
    
    @inbounds for config in configs
        (config & check_mask) != check_value && continue
        
        if probe_config_feasible!(problem.buffer, problem, region.vars, config)
            projected = project_single_config(config, unfixed_positions)
            or_all |= projected
            and_all &= projected
            found_any = true
            
            # Early termination: if aggregates saturate, no forced var possible
            if (and_all & var_mask) == 0 && ((~or_all) & var_mask) == 0
                return nothing
            end
        end
    end
    
    !found_any && return nothing
    
    forced_to_1 = and_all & var_mask
    forced_to_0 = (~or_all) & var_mask
    
    if forced_to_1 != 0
        bit_mask = forced_to_1 & (-forced_to_1)
        return Clause(bit_mask, bit_mask)
    elseif forced_to_0 != 0
        bit_mask = forced_to_0 & (-forced_to_0)
        return Clause(bit_mask, UInt64(0))
    end
    
    return nothing
end

"""
    detect_forced_variable(configs, n_vars) -> Union{Nothing, Clause}

Detect if any variable is forced across all configurations.
Used by GreedyMerge fast-path.
"""
function detect_forced_variable(configs::Vector{UInt64}, n_vars::Int)
    isempty(configs) && return nothing

    or_all = UInt64(0)
    and_all = ~UInt64(0)

    @inbounds for config in configs
        or_all |= config
        and_all &= config
    end

    var_mask = (UInt64(1) << n_vars) - 1
    forced_to_1 = and_all & var_mask
    forced_to_0 = (~or_all) & var_mask

    if forced_to_1 != 0
        return Clause(forced_to_1 & (-forced_to_1), forced_to_1 & (-forced_to_1))
    elseif forced_to_0 != 0
        return Clause(forced_to_0 & (-forced_to_0), UInt64(0))
    end

    return nothing
end

# ============================================================================
# Configuration Filtering and Probing
# ============================================================================

"""
    filter_feasible_configs(problem, region, configs, measure) -> Vector{UInt64}

Filter configurations compatible with current domains that pass propagation.
Used during branching (caches measures).
"""
function filter_feasible_configs(problem::TNProblem, region::Region, configs::Vector{UInt64}, measure::AbstractMeasure)
    check_mask, check_value = get_region_masks(problem.doms, region.vars)
    feasible = UInt64[]

    @inbounds for config in configs
        (config & check_mask) != check_value && continue
        if probe_config!(problem.buffer, problem, region.vars, config, measure)
            push!(feasible, config)
        end
    end

    return feasible
end

"""
    probe_config!(buffer, problem, vars, config, measure) -> Bool

Test if a configuration is feasible and cache its measure.
Used during branching phase.
"""
function probe_config!(buffer::SolverBuffer, problem::TNProblem, vars::Vector{Int}, config::UInt64, measure::AbstractMeasure)
    mask = (UInt64(1) << length(vars)) - 1
    scratch = probe_assignment_core!(problem, buffer, problem.doms, vars, mask, config)

    is_feasible = scratch[1] != DM_NONE
    if is_feasible
        buffer.branching_cache[Clause(mask, config)] = measure_core(problem.static, scratch, measure)
    end

    return is_feasible
end

"""
    probe_config_feasible!(buffer, problem, vars, config) -> Bool

Fast feasibility check without measure computation.
Used during reduction phase where we only need feasibility.
"""
@inline function probe_config_feasible!(buffer::SolverBuffer, problem::TNProblem, vars::Vector{Int}, config::UInt64)
    mask = (UInt64(1) << length(vars)) - 1
    scratch = probe_assignment_core!(problem, buffer, problem.doms, vars, mask, config)
    return scratch[1] != DM_NONE
end

# ============================================================================
# Helper Functions
# ============================================================================

@inline function get_region_masks(doms::Vector{DomainMask}, vars::Vector{Int})
    return mask_value(doms, vars, UInt64)
end

function extract_unfixed_vars(doms::Vector{DomainMask}, vars::Vector{Int})
    unfixed_positions = Int[]
    unfixed_vars = Int[]

    @inbounds for (i, v) in enumerate(vars)
        if !is_fixed(doms[v])
            push!(unfixed_positions, i)
            push!(unfixed_vars, v)
        end
    end

    return (unfixed_positions, unfixed_vars)
end

function project_configs(configs::Vector{UInt64}, positions::Vector{Int})
    projected = UInt64[]

    @inbounds for config in configs
        new_config = project_single_config(config, positions)
        push!(projected, new_config)
    end

    unique!(projected)
    return projected
end

@inline function project_single_config(config::UInt64, positions::Vector{Int})
    new_config = UInt64(0)
    @inbounds for (new_i, old_i) in enumerate(positions)
        if (config >> (old_i - 1)) & 1 == 1
            new_config |= UInt64(1) << (new_i - 1)
        end
    end
    return new_config
end

# ============================================================================
# GreedyMerge with Gamma-1 Fast Path
# ============================================================================

"""
    OptimalBranchingCore.optimal_branching_rule(table, variables, problem, m, ::GreedyMerge)

Compute optimal branching rule with fast-path gamma=1 detection.
If any variable is forced, returns immediately without running GreedyMerge.
"""
function OptimalBranchingCore.optimal_branching_rule(table::BranchingTable, variables::Vector, problem::TNProblem, m::AbstractMeasure, ::GreedyMerge)
    n_vars = table.bit_length

    # Fast-path: detect forced variables FIRST (before expensive bit_clauses)
    if n_vars > 0 && !isempty(table.table)
        configs = UInt64[first(entry) for entry in table.table]
        forced_clause = detect_forced_variable(configs, n_vars)

        if !isnothing(forced_clause)
            sr = OptimalBranchingCore.size_reduction(problem, m, forced_clause, variables)
            return OptimalBranchingCore.OptimalBranchingResult(
                DNF([forced_clause]), [Float64(sr)], 1.0
            )
        end
    end

    # Only compute candidates if fast-path didn't apply
    candidates = OptimalBranchingCore.bit_clauses(table)

    # Run GreedyMerge
    result = OptimalBranchingCore.greedymerge(candidates, problem, variables, m)

    # Fallback for degenerate results
    if n_vars > 0 && (result.γ == Inf || isempty(OptimalBranchingCore.get_clauses(result)) ||
                     all(cl -> cl.mask == 0, OptimalBranchingCore.get_clauses(result)))
        cl_0 = Clause(UInt64(1), UInt64(0))
        cl_1 = Clause(UInt64(1), UInt64(1))
        sr_0 = OptimalBranchingCore.size_reduction(problem, m, cl_0, variables)
        sr_1 = OptimalBranchingCore.size_reduction(problem, m, cl_1, variables)
        γ = OptimalBranchingCore.complexity_bv([Float64(sr_0), Float64(sr_1)])
        return OptimalBranchingCore.OptimalBranchingResult(
            DNF([cl_0, cl_1]), [Float64(sr_0), Float64(sr_1)], γ
        )
    end

    return result
end

# ============================================================================
# IPSolver with Gamma-1 Fast Path
# ============================================================================

"""
    OptimalBranchingCore.optimal_branching_rule(table, variables, problem, m, solver::IPSolver)

Compute optimal branching rule with fast-path gamma=1 detection.
If any variable is forced, returns immediately without running IP solver.
"""
function OptimalBranchingCore.optimal_branching_rule(table::BranchingTable, variables::Vector, problem::TNProblem, m::AbstractMeasure, solver::IPSolver)
    n_vars = table.bit_length

    # Fast-path: detect forced variables (same as GreedyMerge)
    if n_vars > 0 && !isempty(table.table)
        configs = UInt64[first(entry) for entry in table.table]
        forced_clause = detect_forced_variable(configs, n_vars)

        if !isnothing(forced_clause)
            sr = OptimalBranchingCore.size_reduction(problem, m, forced_clause, variables)
            return OptimalBranchingCore.OptimalBranchingResult(
                DNF([forced_clause]), [Float64(sr)], 1.0
            )
        end
    end

    # Run IP solver (default implementation)
    candidates = OptimalBranchingCore.candidate_clauses(table)
    isempty(candidates) && return OptimalBranchingCore.OptimalBranchingResult(DNF(Clause{UInt64}[]), Float64[], Inf)
    Δρ = [Float64(OptimalBranchingCore.size_reduction(problem, m, c, variables)) for c in candidates]
    return OptimalBranchingCore.minimize_γ(table, candidates, Δρ, solver)
end
