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
# Branching Result Computation
# ============================================================================

"""
    compute_branching_result(cache, problem, var_id, measure, solver) -> (result, variables)

Compute the optimal branching result for a variable's region.

# Arguments
- `cache::RegionCache`: Cache for region data
- `problem::TNProblem`: Current problem state
- `var_id::Int`: Center variable for the region
- `measure::AbstractMeasure`: Problem measure
- `solver::AbstractSetCoverSolver`: Set cover solver for branching

# Returns
- `result`: OptimalBranchingResult or `nothing` if no valid branching
- `variables`: List of unfixed variables in the region
"""
function compute_branching_result(
    cache::RegionCache,
    problem::TNProblem,
    var_id::Int,
    measure::AbstractMeasure,
    set_cover_solver::AbstractSetCoverSolver
)
    projected, unfixed_vars = prepare_branching_configs(cache, problem, var_id, measure)
    isnothing(projected) && return (nothing, unfixed_vars)

    # Build branching table and compute optimal rule
    table = BranchingTable(length(unfixed_vars), [[c] for c in projected])
    result = OptimalBranchingCore.optimal_branching_rule(table, unfixed_vars, problem, measure, set_cover_solver)
    return (result, unfixed_vars)
end

"""
    find_forced_assignment(cache, problem, var_id, measure) -> Union{Nothing, Tuple}

Check if a region has a forced variable assignment (gamma=1).

This is optimized for the reduction phase:
- Does NOT run GreedyMerge if no forced variable is found
- Returns immediately if no gamma=1 exists
- Much faster than `compute_branching_result` when only detecting reductions

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
    projected, unfixed_vars = prepare_branching_configs(cache, problem, var_id, measure)
    isnothing(projected) && return nothing

    # Fast-path: detect if any variable is forced
    forced_clause = detect_forced_variable(projected, length(unfixed_vars))
    isnothing(forced_clause) && return nothing

    return (forced_clause, unfixed_vars)
end

"""
    prepare_branching_configs(cache, problem, var_id, measure) -> (configs, variables)

Prepare projected configurations for branching computation.

This is the shared preprocessing step for both `compute_branching_result`
and `find_forced_assignment`.

# Returns
- `configs`: Projected configurations on unfixed variables, or `nothing` if empty
- `variables`: List of unfixed variables (or region vars if nothing)
"""
function prepare_branching_configs(cache::RegionCache, problem::TNProblem, var_id::Int, measure::AbstractMeasure)
    region, cached_configs = get_region_data!(cache, problem, var_id)

    # Filter configs compatible with current domains
    feasible_configs = filter_feasible_configs(problem, region, cached_configs, measure)
    isempty(feasible_configs) && return (nothing, region.vars)

    # Extract unfixed variables
    unfixed_positions, unfixed_vars = extract_unfixed_vars(problem.doms, region.vars)
    isempty(unfixed_vars) && return (nothing, region.vars)

    # Project configs onto unfixed variables
    projected = project_configs(feasible_configs, unfixed_positions)

    return (projected, unfixed_vars)
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
    extract_unfixed_vars(doms, vars) -> (positions, unfixed_vars)

Extract positions and IDs of unfixed variables from a variable list.
"""
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

"""
    project_configs(configs, positions) -> Vector{UInt64}

Project configurations onto a subset of variable positions.
"""
function project_configs(configs::Vector{UInt64}, positions::Vector{Int})
    projected = UInt64[]

    @inbounds for config in configs
        new_config = UInt64(0)
        for (new_i, old_i) in enumerate(positions)
            if (config >> (old_i - 1)) & 1 == 1
                new_config |= UInt64(1) << (new_i - 1)
            end
        end
        push!(projected, new_config)
    end

    unique!(projected)
    return projected
end

# ============================================================================
# Configuration Filtering
# ============================================================================

"""
    get_region_masks(doms, vars) -> (mask, value)

Compute bitmasks for fixed variables in a region.
"""
@inline function get_region_masks(doms::Vector{DomainMask}, vars::Vector{Int})
    return mask_value(doms, vars, UInt64)
end

"""
    filter_feasible_configs(problem, region, configs, measure) -> Vector{UInt64}

Filter configurations that are compatible with current domain assignments
and pass constraint propagation.
"""
function filter_feasible_configs(problem::TNProblem, region::Region, configs::Vector{UInt64}, measure::AbstractMeasure)
    check_mask, check_value = get_region_masks(problem.doms, region.vars)
    feasible = UInt64[]

    @inbounds for config in configs
        # Skip if incompatible with fixed assignments
        (config & check_mask) != check_value && continue

        # Check if propagation succeeds
        if probe_config!(problem.buffer, problem, region.vars, config, measure)
            push!(feasible, config)
        end
    end

    return feasible
end

"""
    probe_config!(buffer, problem, vars, config, measure) -> Bool

Test if a configuration is feasible by probing and propagating.
Caches the resulting measure if feasible.
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

# ============================================================================
# Forced Variable Detection (Gamma=1)
# ============================================================================

"""
    detect_forced_variable(configs, n_vars) -> Union{Nothing, Clause}

Detect if any variable is forced to a fixed value across all configurations.

Uses bitwise OR/AND aggregation:
- Forced to 1: bit is 1 in ALL configs (appears in AND result)
- Forced to 0: bit is 0 in ALL configs (doesn't appear in OR result)

# Arguments
- `configs`: Vector of configuration bitmasks
- `n_vars`: Number of variables in the configurations

# Returns
- `nothing` if no forced variable exists
- `Clause` representing the forced assignment
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

    # Return first forced variable if any
    if forced_to_1 != 0
        bit_mask = forced_to_1 & (-forced_to_1)  # Isolate lowest set bit
        return Clause(bit_mask, bit_mask)
    elseif forced_to_0 != 0
        bit_mask = forced_to_0 & (-forced_to_0)
        return Clause(bit_mask, UInt64(0))
    end

    return nothing
end

# ============================================================================
# Optimal Branching Rule with Gamma-1 Fast Path
# ============================================================================

"""
    OptimalBranchingCore.optimal_branching_rule(table, variables, problem, m, solver::GreedyMerge)

Compute optimal branching rule with fast-path gamma=1 detection.

Before running the expensive GreedyMerge algorithm, we check if any variable
has a uniform value across all configurations (forced variable). If found,
we can return immediately with gamma=1.

# Algorithm
1. Compute bitwise OR and AND across all configurations
2. Check for forced-to-1 bits: (AND & mask) != 0
3. Check for forced-to-0 bits: (~OR & mask) != 0
4. If any forced bit exists, return single-clause result with gamma=1
5. Otherwise, run full GreedyMerge
"""
function OptimalBranchingCore.optimal_branching_rule(table::BranchingTable, variables::Vector, problem::TNProblem, m::AbstractMeasure, ::GreedyMerge)
    candidates = OptimalBranchingCore.bit_clauses(table)
    n_vars = table.bit_length

    # Fast-path: detect forced variables
    if n_vars > 0 && !isempty(table.table)
        # Extract configs from table entries
        configs = UInt64[first(entry) for entry in table.table]
        forced_clause = detect_forced_variable(configs, n_vars)

        if !isnothing(forced_clause)
            sr = OptimalBranchingCore.size_reduction(problem, m, forced_clause, variables)
            return OptimalBranchingCore.OptimalBranchingResult(
                DNF([forced_clause]), [Float64(sr)], 1.0
            )
        end
    end

    # Run GreedyMerge
    result = OptimalBranchingCore.greedymerge(candidates, problem, variables, m)

    # Fallback: if GreedyMerge returns degenerate result (empty clause or γ=Inf),
    # use simple 0/1 branching on first variable
    if n_vars > 0 && (result.γ == Inf || isempty(OptimalBranchingCore.get_clauses(result)) ||
                     all(cl -> cl.mask == 0, OptimalBranchingCore.get_clauses(result)))
        # Simple 0/1 branching: var[1]=0 and var[1]=1
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
