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

"""
    VarsCutoff <: AbstractCutoffStrategy

Cutoff when the number of unfixed variables drops to or below a threshold.
This is the standard cutoff used in march_cu (`-n` flag).

# Example
```julia
# Stop cubing when <= 50 variables remain unfixed
cutoff = VarsCutoff(50)
```
"""
struct VarsCutoff <: AbstractCutoffStrategy
    max_free_vars::Int
end

"""
    RatioCutoff <: AbstractCutoffStrategy

Cutoff when the ratio of unfixed variables to initial variables drops below threshold.
More portable across different problem sizes than absolute variable count.

# Example
```julia
# Stop cubing when 70% of variables are fixed (30% remain)
cutoff = RatioCutoff(0.3)
```
"""
struct RatioCutoff <: AbstractCutoffStrategy
    ratio::Float64
end

"""
    ProductCutoff <: AbstractCutoffStrategy

Simple product-based cutoff: `|σ_dec| × |σ_all| > θ`

Where:
- `|σ_dec|`: number of decision variables (cube literals)  
- `|σ_all|`: total fixed variables (decisions + propagated)
- `θ`: threshold

This is simpler than march's formula and doesn't require normalizing by remaining vars.

# Example
```julia
cutoff = ProductCutoff(500)   # Cutoff when dec * all > 500
cutoff = ProductCutoff(300)   # Earlier cutoff (shallower cubes)
cutoff = ProductCutoff(800)   # Later cutoff (deeper cubes)
```
"""
struct ProductCutoff <: AbstractCutoffStrategy
    threshold::Int
end

ProductCutoff() = ProductCutoff(500)

"""
    DifficultyCutoff <: AbstractCutoffStrategy

March-style difficulty-based cutoff: `d = |φ_dec|² · (|φ_dec| + |φ_imp|) / n > t_cc`

Dynamic threshold with growth on decision and decay on refutation.
"""
mutable struct DifficultyCutoff <: AbstractCutoffStrategy
    initial_threshold::Float64
    growth_rate::Float64
    decay_rate::Float64
    verbose::Bool
    current_threshold::Float64
    max_difficulty_seen::Float64
end

function DifficultyCutoff(; initial::Float64=100.0, growth::Float64=1.03, decay::Float64=0.7, verbose::Bool=false)
    DifficultyCutoff(initial, growth, decay, verbose, initial, 0.0)
end

"""
    GammaRatioCutoff <: AbstractCutoffStrategy

Cutoff based on the ratio of current gamma to initial gamma.
When gamma drops to a certain fraction of the initial gamma, emit cube.

The idea: gamma approaching 1.0 indicates the problem is highly constrained,
meaning CDCL's unit propagation will be very effective. So we should hand off
to CDCL when gamma/gamma_0 falls below a threshold.

# Example
```julia
# Stop cubing when gamma drops to 97% of initial gamma
cutoff = GammaRatioCutoff(0.97)
```
"""
struct GammaRatioCutoff <: AbstractCutoffStrategy
    ratio_threshold::Float64
end

GammaRatioCutoff() = GammaRatioCutoff(0.97)

function reset!(cutoff::DifficultyCutoff)
    cutoff.current_threshold = cutoff.initial_threshold
    cutoff.max_difficulty_seen = 0.0
end

@inline function compute_difficulty(n_decisions::Int, n_implied::Int, n_free::Int)
    n_free == 0 && return Inf
    dec = Float64(n_decisions)
    return dec * dec * (dec + n_implied) / n_free
end

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

function should_emit_cube(strategy::VarsCutoff, initial_nvars::Int, doms::Vector{DomainMask}, depth::Int, n_cubes::Int)
    return count_unfixed(doms) <= strategy.max_free_vars
end

function should_emit_cube(strategy::RatioCutoff, initial_nvars::Int, doms::Vector{DomainMask}, depth::Int, n_cubes::Int)
    return count_unfixed(doms) <= initial_nvars * strategy.ratio
end

# DifficultyCutoff needs more context - we use a forward declaration pattern
# The actual implementation is below after CnCContext is defined

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

    # Gamma tracking for GammaRatioCutoff
    initial_gamma::Float64  # First gamma seen (0.0 = not yet set)
end

@inline function is_solved(ctx::CnCContext, doms::Vector{DomainMask})
    if isempty(ctx.target_vars)
        return count_unfixed(doms) == 0
    else
        return all(v -> is_fixed(doms[v]), ctx.target_vars)
    end
end

# ============================================================================
# Context-aware Cutoff Evaluation (needs CnCContext)
# ============================================================================

"""
Evaluate ProductCutoff: |σ_dec| × |σ_all| > θ
Simple and effective - no normalization needed.
"""
function should_emit_cube(ctx::CnCContext, strategy::ProductCutoff, doms::Vector{DomainMask})
    n_free = count_unfixed(doms)
    n_free == 0 && return true
    
    n_decisions = length(ctx.current_path)  # |σ_dec|
    n_total_fixed = ctx.initial_nvars - n_free  # |σ_all|
    
    product = n_decisions * n_total_fixed
    return product > strategy.threshold
end

"""
Evaluate DifficultyCutoff using the difficulty metric from march_cu paper.
d(cid) = |φ_dec|² · (|φ_dec| + |φ_imp|) / n
"""
function should_emit_cube(ctx::CnCContext, strategy::DifficultyCutoff, doms::Vector{DomainMask})
    n_free = count_unfixed(doms)
    n_free == 0 && return true
    
    n_decisions = length(ctx.current_path)  # |φ_dec|
    n_total_fixed = ctx.initial_nvars - n_free
    n_implied = n_total_fixed - n_decisions  # |φ_imp| = total fixed - decisions
    n_implied = max(0, n_implied)  # Safety: can't be negative
    
    difficulty = compute_difficulty(n_decisions, n_implied, n_free)
    
    # Track max difficulty seen
    if difficulty > strategy.max_difficulty_seen
        strategy.max_difficulty_seen = difficulty
        if strategy.verbose
            @info "DifficultyCutoff" n_dec=n_decisions n_imp=n_implied n_free difficulty threshold=strategy.current_threshold
        end
    end
    
    should_cutoff = difficulty > strategy.current_threshold
    if should_cutoff && strategy.verbose
        @info "CUTOFF!" n_dec=n_decisions difficulty threshold=strategy.current_threshold
    end
    return should_cutoff
end

# Fallback: use generic signature for VarsCutoff/RatioCutoff
function should_emit_cube(ctx::CnCContext, strategy::AbstractCutoffStrategy, doms::Vector{DomainMask})
    return should_emit_cube(strategy, ctx.initial_nvars, doms, 0, length(ctx.cubes))
end

"""
Evaluate GammaRatioCutoff: gamma / initial_gamma < threshold
When the ratio drops below threshold, the problem is highly constrained and CDCL will be effective.
"""
function should_emit_cube(ctx::CnCContext, strategy::GammaRatioCutoff, doms::Vector{DomainMask}, gamma::Float64)
    n_free = count_unfixed(doms)
    n_free == 0 && return true

    # Record initial gamma on first call
    if ctx.initial_gamma == 0.0
        ctx.initial_gamma = gamma
        return false  # Never cutoff on first branching
    end

    ratio = gamma / ctx.initial_gamma
    return ratio < strategy.ratio_threshold
end

# Fallback for non-gamma cutoffs: ignore gamma parameter
function should_emit_cube(ctx::CnCContext, strategy::AbstractCutoffStrategy, doms::Vector{DomainMask}, gamma::Float64)
    return should_emit_cube(ctx, strategy, doms)
end

"""
Called after each decision (branching). Increases threshold.
"""
function on_decision!(strategy::DifficultyCutoff)
    strategy.current_threshold *= strategy.growth_rate
end
on_decision!(::AbstractCutoffStrategy) = nothing

"""
Called when a branch is quickly refuted. Decreases threshold to emit cubes earlier.
"""
function on_refutation!(strategy::DifficultyCutoff)
    strategy.current_threshold *= strategy.decay_rate
end
on_refutation!(::AbstractCutoffStrategy) = nothing

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
    cutoff isa DifficultyCutoff && reset!(cutoff)

    ctx = CnCContext(
        problem.static, problem.stats, problem.buffer,
        config, reducer, cache,
        cutoff,
        count_unfixed(problem.doms),
        target_vars,
        Cube[], Int[], Int[],
        0.0  # initial_gamma (set on first branching)
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
        record_sat_leaf!(ctx.stats)
        push!(ctx.cubes, Cube(copy(ctx.current_path), depth, false))
        return Result(true, copy(doms), copy(ctx.stats))
    end

    # Reduction phase (same as _bbsat!)
    current_doms = doms
    if ctx.reducer isa GammaOneReducer
        reduced_doms, has_contra = reduce_with_gamma_one_cnc!(ctx, doms)

        if has_contra
            record_unsat_leaf!(ctx.stats)
            restore_path!(ctx, path_len_at_entry)
            return Result(false, DomainMask[], copy(ctx.stats))
        end

        current_doms = reduced_doms

        if is_solved(ctx, current_doms)
            record_sat_leaf!(ctx.stats)
            push!(ctx.cubes, Cube(copy(ctx.current_path), depth, false))
            restore_path!(ctx, path_len_at_entry)
            return Result(true, copy(current_doms), copy(ctx.stats))
        end
    end

    problem = TNProblem(ctx.static, current_doms, ctx.stats, ctx.buffer)

    # Variable selection and branching - compute gamma first for cutoff decision
    empty!(ctx.buffer.branching_cache)
    clauses, variables, gamma = findbest(ctx.region_cache, problem, ctx.config.measure,
        ctx.config.set_cover_solver, ctx.config.selector, depth)

    if isnothing(clauses)
        record_unsat_leaf!(ctx.stats)
        restore_path!(ctx, path_len_at_entry)
        return Result(false, DomainMask[], copy(ctx.stats))
    end

    # Check cutoff - emit cube and backtrack (gamma is now available for GammaRatioCutoff)
    if should_emit_cube(ctx, ctx.cutoff, current_doms, gamma)
        push!(ctx.cubes, Cube(copy(ctx.current_path), depth, false))
        restore_path!(ctx, path_len_at_entry)
        return Result(false, DomainMask[], copy(ctx.stats))
    end

    # Single branch = forced assignment
    if length(clauses) == 1
        subproblem_doms = probe_branch!(problem, ctx.buffer, current_doms, clauses[1], variables)

        if has_contradiction(subproblem_doms)
            record_unsat_leaf!(ctx.stats)
            restore_path!(ctx, path_len_at_entry)
            return Result(false, DomainMask[], copy(ctx.stats))
        end

        record_reduction_node!(ctx.stats)

        # Record literals
        append_branch_literals!(ctx, clauses[1], variables, current_doms, subproblem_doms)

        result = _bbsat_cnc!(ctx, copy(subproblem_doms), depth)
        restore_path!(ctx, path_len_at_entry)
        return result
    end

    # Multi-branch: record branching node
    record_branching_node!(ctx.stats, length(clauses))

    if !isempty(variables)
        push!(ctx.branching_vars, variables[1])
    end

    # Notify cutoff of decision (increases threshold for DifficultyCutoff)
    on_decision!(ctx.cutoff)

    path_len_before_branches = length(ctx.current_path)

    @inbounds for i in 1:length(clauses)
        clause = clauses[i]
        subproblem_doms = probe_branch!(problem, ctx.buffer, current_doms, clause, variables)

        if has_contradiction(subproblem_doms)
            record_unsat_leaf!(ctx.stats)
            # Quick refutation - decrease threshold to emit cubes earlier
            on_refutation!(ctx.cutoff)
            continue
        end

        # Record child explored with assignment counts
        direct_vars = count_ones(clause.mask)
        total_vars_fixed = count_unfixed(current_doms) - count_unfixed(subproblem_doms)
        record_child_explored!(ctx.stats, direct_vars, total_vars_fixed - direct_vars)

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
    # Use single problem view - doms will be modified in-place
    problem = TNProblem(ctx.static, doms, ctx.stats, ctx.buffer)

    # Check only the first limit variables (or fewer if not available)
    sorted_vars = get_sorted_unfixed_vars(problem)
    isempty(sorted_vars) && return (doms, false)
    
    n_vars = length(sorted_vars)
    # Safe to access limit because caller checks ctx.reducer isa GammaOneReducer
    limit = (ctx.reducer::GammaOneReducer).limit
    scan_limit = limit == 0 ? n_vars : min(n_vars, limit)
    
    for scan_pos in 1:scan_limit
        var_id = sorted_vars[scan_pos]
        
        # Skip if variable became fixed
        is_fixed(doms[var_id]) && continue
        
        result = find_forced_assignment(ctx.region_cache, problem, var_id, ctx.config.measure)
        
        if !isnothing(result)
            clause, variables = result
            
            # Record statistics before modification
            old_unfixed = count_unfixed(doms)
            
            # Apply assignment in-place
            success = apply_assignment_inplace!(problem, ctx.buffer, doms, variables, clause.mask, clause.val)

            if !success
                return (doms, true)
            end

            # Record reduction assignments
            direct_vars = count_ones(clause.mask)
            total_vars_fixed = old_unfixed - count_unfixed(doms)
            record_reduction!(ctx.stats, direct_vars, total_vars_fixed - direct_vars)
        end
    end

    return (doms, false)
end

@inline function restore_path!(ctx::CnCContext, target_len::Int)
    while length(ctx.current_path) > target_len
        pop!(ctx.current_path)
    end
end

function append_branch_literals!(ctx::CnCContext, clause::Clause, variables::Vector{Int},
    old_doms::Vector{DomainMask}, new_doms::Vector{DomainMask})
    # Only add clause literals (decision variables directly fixed by branching)
    # Propagated and reduced variables are intentionally excluded
    for (i, var_id) in enumerate(variables)
        bit = UInt64(1) << (i - 1)
        if (clause.mask & bit) != 0
            lit = (clause.val & bit) != 0 ? var_id : -var_id
            push!(ctx.current_path, lit)
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
        n_cubes=result.n_cubes,
        n_refuted=result.n_refuted,
        n_leaves=length(non_refuted_idx),
        avg_weight=isempty(weights) ? NaN : sum(weights) / length(weights),
        avg_leaf_weight=isempty(leaf_weights) ? NaN : sum(leaf_weights) / length(leaf_weights),
        min_weight=isempty(weights) ? 0 : minimum(weights),
        max_weight=isempty(weights) ? 0 : maximum(weights)
    )
end
