# ============================================================================
# Cube-and-Conquer
#
# This module implements Cube-and-Conquer solving. The cubing phase uses
# the same search logic as bbsat!, but emits cubes when cutoff is reached
# instead of continuing to solve.
# ============================================================================

# ============================================================================
# Cutoff Strategies
# ============================================================================

abstract type AbstractCutoffStrategy end

struct DepthCutoff <: AbstractCutoffStrategy
    max_depth::Int
end

struct VarsCutoff <: AbstractCutoffStrategy
    max_free_vars::Int
end

struct RatioCutoff <: AbstractCutoffStrategy
    ratio::Float64
end

struct DynamicCutoff <: AbstractCutoffStrategy
    base_ratio::Float64
    depth_growth::Float64
end

DynamicCutoff() = DynamicCutoff(0.3, 0.03)

"""
    MarchCutoff <: AbstractCutoffStrategy

March-style adaptive cutoff that adjusts threshold based on search progress.
- When a branch is refuted (UNSAT), increase threshold (go deeper)
- When exploration succeeds, decrease threshold (emit cubes earlier)

This balances lookahead effort with CDCL solving efficiency.

# Fields
- `initial_threshold::Float64`: Starting cutoff ratio (default: 0.5)
- `increase_rate::Float64`: Rate to increase threshold on refutation (default: 0.05)
- `decrease_rate::Float64`: Rate to decrease threshold on success (default: 0.30)
- `min_threshold::Float64`: Minimum threshold (default: 0.2)
- `max_threshold::Float64`: Maximum threshold (default: 0.9)
"""
mutable struct MarchCutoff <: AbstractCutoffStrategy
    initial_threshold::Float64
    increase_rate::Float64
    decrease_rate::Float64
    min_threshold::Float64
    max_threshold::Float64
    # Runtime state
    current_threshold::Float64
    refuted_count::Int
    success_count::Int
end

function MarchCutoff(;
    initial_threshold::Float64=0.5,
    increase_rate::Float64=0.05,
    decrease_rate::Float64=0.30,
    min_threshold::Float64=0.2,
    max_threshold::Float64=0.9
)
    MarchCutoff(initial_threshold, increase_rate, decrease_rate,
                min_threshold, max_threshold, initial_threshold, 0, 0)
end

struct CubeLimitCutoff <: AbstractCutoffStrategy
    max_cubes::Int
    fallback::AbstractCutoffStrategy
end

CubeLimitCutoff(max_cubes::Int) = CubeLimitCutoff(max_cubes, DynamicCutoff())

# ============================================================================
# Cube Representation
# ============================================================================

struct Cube
    literals::Vector{Int}
    depth::Int
    is_refuted::Bool
end

Cube(literals::Vector{Int}, depth::Int) = Cube(literals, depth, false)

struct CubeResult
    cubes::Vector{Cube}
    n_cubes::Int
    n_refuted::Int
    stats::BranchingStats
    nvars::Int
    branching_vars::Vector{Int}
end

struct CnCStats
    num_cubes::Int
    num_refuted::Int
    cubing_time::Float64
    avg_cube_vars::Float64
    cubes_solved::Int
    total_decisions::Int
    total_conflicts::Int
    avg_decisions::Float64
    avg_conflicts::Float64
    avg_solve_time::Float64
    total_solve_time::Float64
end

function Base.show(io::IO, s::CnCStats)
    print(io, "CnCStats(cubes=$(s.num_cubes), refuted=$(s.num_refuted), " *
              "cubing=$(round(s.cubing_time, digits=2))s, " *
              "solved=$(s.cubes_solved), " *
              "avg_dec=$(round(s.avg_decisions, digits=1)), " *
              "avg_conf=$(round(s.avg_conflicts, digits=1)), " *
              "solve=$(round(s.total_solve_time, digits=2))s)")
end

struct CnCResult
    status::Symbol
    solution::Vector{Int32}
    cube_result::CubeResult
    cnc_stats::CnCStats
end

function Base.show(io::IO, r::CnCResult)
    print(io, "CnCResult(:$(r.status), $(r.cnc_stats))")
end

# ============================================================================
# Cutoff Evaluation
# ============================================================================

function should_emit_cube(strategy::DepthCutoff, initial_nvars::Int, doms::Vector{DomainMask}, depth::Int, n_cubes::Int)
    return depth >= strategy.max_depth
end

function should_emit_cube(strategy::VarsCutoff, initial_nvars::Int, doms::Vector{DomainMask}, depth::Int, n_cubes::Int)
    return count_unfixed(doms) <= strategy.max_free_vars
end

function should_emit_cube(strategy::RatioCutoff, initial_nvars::Int, doms::Vector{DomainMask}, depth::Int, n_cubes::Int)
    return count_unfixed(doms) <= initial_nvars * strategy.ratio
end

function should_emit_cube(strategy::DynamicCutoff, initial_nvars::Int, doms::Vector{DomainMask}, depth::Int, n_cubes::Int)
    cutoff_ratio = min(strategy.base_ratio + strategy.depth_growth * depth, 0.95)
    return count_unfixed(doms) <= initial_nvars * cutoff_ratio
end

function should_emit_cube(strategy::MarchCutoff, initial_nvars::Int, doms::Vector{DomainMask}, depth::Int, n_cubes::Int)
    # Use current adaptive threshold
    return count_unfixed(doms) <= initial_nvars * strategy.current_threshold
end

"""
    on_branch_refuted!(strategy::MarchCutoff)

Called when a branch is refuted (leads to contradiction).
Increases threshold to explore deeper before emitting cubes.
"""
function on_branch_refuted!(strategy::MarchCutoff)
    strategy.refuted_count += 1
    strategy.current_threshold = min(
        strategy.current_threshold + strategy.increase_rate,
        strategy.max_threshold
    )
end

"""
    on_branch_success!(strategy::MarchCutoff)

Called when a branch completes successfully (cube emitted or solved).
Decreases threshold to emit cubes earlier.
"""
function on_branch_success!(strategy::MarchCutoff)
    strategy.success_count += 1
    strategy.current_threshold = max(
        strategy.current_threshold * (1 - strategy.decrease_rate),
        strategy.min_threshold
    )
end

"""
    reset!(strategy::MarchCutoff)

Reset the adaptive state for a new cubing session.
"""
function reset!(strategy::MarchCutoff)
    strategy.current_threshold = strategy.initial_threshold
    strategy.refuted_count = 0
    strategy.success_count = 0
end

function should_emit_cube(strategy::CubeLimitCutoff, initial_nvars::Int, doms::Vector{DomainMask}, depth::Int, n_cubes::Int)
    n_cubes >= strategy.max_cubes && return true
    return should_emit_cube(strategy.fallback, initial_nvars, doms, depth, n_cubes)
end

# ============================================================================
# CnC Context
# ============================================================================

mutable struct CnCContext
    # Search state (same as SearchContext)
    static::ConstraintNetwork
    stats::BranchingStats
    buffer::SolverBuffer
    config::OptimalBranchingCore.BranchingStrategy
    reducer::OptimalBranchingCore.AbstractReducer
    region_cache::RegionCache

    # CnC specific
    cutoff::AbstractCutoffStrategy
    initial_nvars::Int
    target_vars::Vector{Int}  # Empty = all vars, otherwise only these need to be fixed
    cubes::Vector{Cube}
    current_path::Vector{Int}
    branching_vars::Vector{Int}
end

@inline function is_solved(ctx::CnCContext, doms::Vector{DomainMask})
    if isempty(ctx.target_vars)
        return count_unfixed(doms) == 0
    else
        return all(v -> is_fixed(doms[v]), ctx.target_vars)
    end
end

# ============================================================================
# Main Entry Point
# ============================================================================

"""
    generate_cubes!(problem, config, reducer, cutoff; target_vars) -> CubeResult

Generate cubes using the same search logic as bbsat!.
When cutoff is reached or target_vars are all fixed, emit a cube and backtrack.
"""
function generate_cubes!(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
    reducer::OptimalBranchingCore.AbstractReducer,
    cutoff::AbstractCutoffStrategy;
    target_vars::Vector{Int}=Int[]
)
    empty!(problem.buffer.branching_cache)
    cache = init_cache(problem, config.table_solver, config.measure,
        config.set_cover_solver, config.selector)

    # Reset adaptive cutoff state
    cutoff isa MarchCutoff && reset!(cutoff)

    ctx = CnCContext(
        problem.static, problem.stats, problem.buffer,
        config, reducer, cache,
        cutoff,
        count_unfixed(problem.doms),
        target_vars,
        Cube[], Int[], Int[]
    )

    _bbsat_cnc!(ctx, problem.doms, 0)

    n_refuted = count(c -> c.is_refuted, ctx.cubes)
    return CubeResult(
        ctx.cubes,
        length(ctx.cubes),
        n_refuted,
        copy(problem.stats),
        length(problem.doms),
        ctx.branching_vars
    )
end

# ============================================================================
# CnC Search (mirrors _bbsat! logic)
# ============================================================================

"""
    _bbsat_cnc!(ctx, doms, depth) -> Result

Internal recursive function for CnC. Same logic as _bbsat!, but:
- Emits cube when cutoff is reached
- Returns found=false to trigger backtracking after emitting cube
- Returns found=true when SAT solution is found (stops search)
"""
function _bbsat_cnc!(ctx::CnCContext, doms::Vector{DomainMask}, depth::Int)
    path_len_at_entry = length(ctx.current_path)

    # Check if solved (target_vars all fixed)
    if is_solved(ctx, doms)
        push!(ctx.cubes, Cube(copy(ctx.current_path), depth, false))
        # Notify adaptive cutoff of success
        ctx.cutoff isa MarchCutoff && on_branch_success!(ctx.cutoff)
        return Result(true, copy(doms), copy(ctx.stats))
    end

    # Reduction phase (same as _bbsat!)
    current_doms = doms
    if ctx.reducer isa GammaOneReducer
        reduced_doms, has_contra = reduce_with_gamma_one_cnc!(ctx, doms)

        if has_contra
            restore_path!(ctx, path_len_at_entry)
            # Notify adaptive cutoff of refutation
            ctx.cutoff isa MarchCutoff && on_branch_refuted!(ctx.cutoff)
            return Result(false, DomainMask[], copy(ctx.stats))
        end

        current_doms = reduced_doms

        if is_solved(ctx, current_doms)
            push!(ctx.cubes, Cube(copy(ctx.current_path), depth, false))
            restore_path!(ctx, path_len_at_entry)
            return Result(true, copy(current_doms), copy(ctx.stats))
        end
    end

    # Check cutoff - emit cube and backtrack
    if should_emit_cube(ctx.cutoff, ctx.initial_nvars, current_doms, depth, length(ctx.cubes))
        push!(ctx.cubes, Cube(copy(ctx.current_path), depth, false))
        restore_path!(ctx, path_len_at_entry)
        # Notify adaptive cutoff of success (cube emitted)
        ctx.cutoff isa MarchCutoff && on_branch_success!(ctx.cutoff)
        return Result(false, DomainMask[], copy(ctx.stats))
    end

    problem = TNProblem(ctx.static, current_doms, ctx.stats, ctx.buffer)

    # Variable selection and branching (same as _bbsat!)
    empty!(ctx.buffer.branching_cache)
    clauses, variables = findbest(ctx.region_cache, problem, ctx.config.measure,
        ctx.config.set_cover_solver, ctx.config.selector, depth)

    if isnothing(clauses)
        restore_path!(ctx, path_len_at_entry)
        # Notify adaptive cutoff of refutation
        ctx.cutoff isa MarchCutoff && on_branch_refuted!(ctx.cutoff)
        return Result(false, DomainMask[], copy(ctx.stats))
    end

    # Single branch = forced assignment
    if length(clauses) == 1
        subproblem_doms = probe_branch!(problem, ctx.buffer, current_doms, clauses[1], variables)

        if has_contradiction(subproblem_doms)
            restore_path!(ctx, path_len_at_entry)
            # Notify adaptive cutoff of refutation
            ctx.cutoff isa MarchCutoff && on_branch_refuted!(ctx.cutoff)
            return Result(false, DomainMask[], copy(ctx.stats))
        end

        # Record literals
        append_branch_literals!(ctx, clauses[1], variables, current_doms, subproblem_doms)

        result = _bbsat_cnc!(ctx, copy(subproblem_doms), depth)
        restore_path!(ctx, path_len_at_entry)
        return result
    end

    # Multi-branch
    record_branch_point!(ctx.stats, length(clauses))

    if !isempty(variables)
        push!(ctx.branching_vars, variables[1])
    end

    path_len_before_branches = length(ctx.current_path)

    @inbounds for i in 1:length(clauses)
        # Check cube limit
        if ctx.cutoff isa CubeLimitCutoff && length(ctx.cubes) >= ctx.cutoff.max_cubes
            break
        end

        clause = clauses[i]
        subproblem_doms = probe_branch!(problem, ctx.buffer, current_doms, clause, variables)

        has_contradiction(subproblem_doms) && continue

        # Record stats
        direct_vars = count_ones(clause.mask)
        total_vars_fixed = count_unfixed(current_doms) - count_unfixed(subproblem_doms)
        record_branch_explored!(ctx.stats, direct_vars, total_vars_fixed)

        # Record literals for this branch
        append_branch_literals!(ctx, clause, variables, current_doms, subproblem_doms)

        result = _bbsat_cnc!(ctx, copy(subproblem_doms), depth + 1)

        # Restore path before trying next branch
        restore_path!(ctx, path_len_before_branches)

        # Found SAT solution - stop search!
        result.found && return result
    end

    restore_path!(ctx, path_len_at_entry)
    return Result(false, DomainMask[], copy(ctx.stats))
end

# ============================================================================
# Helper Functions
# ============================================================================

function reduce_with_gamma_one_cnc!(ctx::CnCContext, doms::Vector{DomainMask})
    current_doms = doms

    while true
        problem = TNProblem(ctx.static, current_doms, ctx.stats, ctx.buffer)

        result = find_gamma_one_region(ctx.region_cache, problem, ctx.config.measure, ctx.reducer)
        isnothing(result) && break

        clauses, variables = result
        new_doms = probe_branch!(problem, ctx.buffer, current_doms, clauses[1], variables)

        if has_contradiction(new_doms)
            return (new_doms, true)
        end

        direct_vars = count_ones(clauses[1].mask)
        total_vars_fixed = count_unfixed(current_doms) - count_unfixed(new_doms)
        record_gamma_one!(ctx.stats, direct_vars, total_vars_fixed)

        # Record literals to path
        append_branch_literals!(ctx, clauses[1], variables, current_doms, new_doms)

        current_doms = copy(new_doms)
    end

    return (current_doms, false)
end

@inline function restore_path!(ctx::CnCContext, target_len::Int)
    while length(ctx.current_path) > target_len
        pop!(ctx.current_path)
    end
end

function append_branch_literals!(ctx::CnCContext, clause::Clause, variables::Vector{Int},
                                  old_doms::Vector{DomainMask}, new_doms::Vector{DomainMask})
    # Add clause literals
    for (i, var_id) in enumerate(variables)
        bit = UInt64(1) << (i - 1)
        if (clause.mask & bit) != 0
            lit = (clause.val & bit) != 0 ? var_id : -var_id
            push!(ctx.current_path, lit)
        end
    end

    # Add propagated literals
    clause_var_set = Set(variables)
    @inbounds for var_id in 1:length(old_doms)
        var_id in clause_var_set && continue

        old_dom = old_doms[var_id]
        new_dom = new_doms[var_id]

        is_fixed(old_dom) && continue
        !is_fixed(new_dom) && continue

        if new_dom == DM_1
            push!(ctx.current_path, var_id)
        elseif new_dom == DM_0
            push!(ctx.current_path, -var_id)
        end
    end
end

# ============================================================================
# Output Formats
# ============================================================================

function write_cubes_icnf(result::CubeResult, filename::String)
    open(filename, "w") do io
        println(io, "c cubes generated by BooleanInference")
        println(io, "c number of cubes $(result.n_cubes), including $(result.n_refuted) refuted")

        for cube in result.cubes
            print(io, "a ")
            for lit in cube.literals
                print(io, lit, " ")
            end
            print(io, "0")
            cube.is_refuted && print(io, " c refuted")
            println(io)
        end
    end
end

function cubes_to_dimacs(result::CubeResult)
    return [cube.literals for cube in result.cubes if !cube.is_refuted]
end

function compute_cube_weights(result::CubeResult)
    return [result.nvars - length(cube.literals) for cube in result.cubes]
end

function cube_statistics(result::CubeResult)
    weights = compute_cube_weights(result)
    non_refuted_idx = findall(c -> !c.is_refuted, result.cubes)
    leaf_weights = weights[non_refuted_idx]

    return (
        n_cubes = result.n_cubes,
        n_refuted = result.n_refuted,
        n_leaves = length(non_refuted_idx),
        avg_weight = isempty(weights) ? NaN : sum(weights) / length(weights),
        avg_leaf_weight = isempty(leaf_weights) ? NaN : sum(leaf_weights) / length(leaf_weights),
        min_weight = isempty(weights) ? 0 : minimum(weights),
        max_weight = isempty(weights) ? 0 : maximum(weights)
    )
end
