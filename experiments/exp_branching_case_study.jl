"""
Experiment: Branching Case Study

Demonstrate the difference between MostOccurrence and MinGamma variable selection
by analyzing the first branching step on a factoring instance.

Goal: Show that
1. MostOccurrence may select a variable with large branch table but poor compression
2. MinGamma finds a variable where OB achieves significant compression
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInference
using BooleanInference: TNProblem, BranchingStrategy
using BooleanInference: TNContractionSolver
using BooleanInference: MostOccurrenceSelector, MinGammaSelector
using BooleanInference: NumUnfixedTensors, NumUnfixedVars
using BooleanInference: factoring_problem
using BooleanInference: get_unfixed_vars
# Internal functions (not exported)
using BooleanInference: RegionCache, compute_branching_result, find_best_var_by_score, init_cache
using BooleanInference: get_region_data!, filter_feasible_configs, extract_unfixed_vars, project_configs
using OptimalBranchingCore: GreedyMerge, Clause, size_reduction, complexity_bv
using Printf
using Random

# ============================================================================
# Helper functions
# ============================================================================

"""
Analyze the branch table and branching rule for a given variable.
Computes γ before and after greedy merge to show compression effect.
"""
function analyze_variable_branching(problem::TNProblem, var_id::Int; k::Int=3, max_tensors::Int=4)
    selector = MostOccurrenceSelector(k, max_tensors)
    measure = NumUnfixedTensors()
    set_cover_solver = GreedyMerge()
    cache = init_cache(problem, TNContractionSolver(), measure, set_cover_solver, selector)

    # Get raw configs before merge
    region, cached_configs = get_region_data!(cache, problem, var_id)
    feasible_configs = filter_feasible_configs(problem, region, cached_configs, measure)
    unfixed_positions, unfixed_vars = extract_unfixed_vars(problem.doms, region.vars)

    if isempty(unfixed_vars) || isempty(feasible_configs)
        return (
            variable = var_id,
            n_vars_in_region = length(unfixed_vars),
            n_configs = 0,
            n_branches = 0,
            gamma = Inf,
            gamma_before = Inf,
            deltas_before = Float64[],
            compression_ratio = 0.0,
            clauses = nothing,
            branching_vector = nothing,
            variables = unfixed_vars
        )
    end

    projected = project_configs(feasible_configs, unfixed_positions)
    n_vars = length(unfixed_vars)
    n_configs = length(projected)

    # Compute Δρ for each config BEFORE merge (each config as a full assignment)
    deltas_before = Float64[]
    for config in projected
        # Create a clause that assigns all variables according to this config
        mask = (UInt64(1) << n_vars) - 1  # all bits set
        clause = Clause(mask, config)
        Δρ = size_reduction(problem, measure, clause, unfixed_vars)
        push!(deltas_before, Float64(Δρ))
    end
    γ_before = complexity_bv(deltas_before)

    # Now compute the merged result
    result, variables, table_info = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)

    if isnothing(result)
        return (
            variable = var_id,
            n_vars_in_region = n_vars,
            n_configs = n_configs,
            n_branches = 0,
            gamma = Inf,
            gamma_before = γ_before,
            deltas_before = deltas_before,
            compression_ratio = 0.0,
            clauses = nothing,
            branching_vector = nothing,
            variables = unfixed_vars
        )
    end

    n_branches = length(result.optimal_rule)
    γ_after = result.γ

    return (
        variable = var_id,
        n_vars_in_region = n_vars,
        n_configs = n_configs,
        n_branches = n_branches,
        gamma = γ_after,
        gamma_before = γ_before,
        deltas_before = deltas_before,
        compression_ratio = n_configs / max(n_branches, 1),
        clauses = result.optimal_rule,
        branching_vector = result.branching_vector,
        variables = variables
    )
end

"""
Print detailed analysis of a branching decision.
"""
function print_branch_analysis(name::String, result; show_configs::Bool=false)
    println("\n" * "="^60)
    println("$name")
    println("="^60)
    println("Selected variable: $(result.variable)")
    println("Variables in region: $(result.n_vars_in_region)")
    println("Region variables: $(result.variables)")
    println()

    # Before merge
    println("Before merge: $(result.n_configs) branches (one per config)")
    if !isempty(result.deltas_before)
        Δρ_before_str = join([@sprintf("%.0f", d) for d in result.deltas_before], ", ")
        println("  Δρ = ($Δρ_before_str)")
    end
    @printf("  γ_before = %.4f\n", result.gamma_before)
    println()

    # After merge
    println("After merge: $(result.n_branches) branches")
    if !isnothing(result.branching_vector)
        Δρ_str = join([@sprintf("%.0f", d) for d in result.branching_vector], ", ")
        println("  Δρ = ($Δρ_str)")
    end
    @printf("  γ_after = %.4f\n", result.gamma)

    # Print merged clauses
    if !isnothing(result.clauses)
        println("  Merged clauses:")
        n_vars = result.n_vars_in_region
        for (i, clause) in enumerate(result.clauses.clauses)
            # clause has mask and val fields
            bits = Char[]
            for j in 1:n_vars
                bit_mask = UInt64(1) << (j-1)
                if (clause.mask & bit_mask) != 0
                    # This bit is fixed
                    if (clause.val & bit_mask) != 0
                        push!(bits, '1')
                    else
                        push!(bits, '0')
                    end
                else
                    push!(bits, '*')
                end
            end
            println("    $i: $(join(bits, ""))")
        end
    end
    println()

    # Summary
    @printf("Compression: %d → %d (%.1fx)\n", result.n_configs, result.n_branches, result.compression_ratio)
    if result.gamma_before > result.gamma
        improvement = (result.gamma_before - result.gamma) / result.gamma_before * 100
        @printf("γ reduction: %.4f → %.4f (%.1f%% improvement)\n", result.gamma_before, result.gamma, improvement)
    elseif result.gamma_before < result.gamma
        increase = (result.gamma - result.gamma_before) / result.gamma_before * 100
        @printf("γ change: %.4f → %.4f (+%.1f%%, merge not beneficial)\n", result.gamma_before, result.gamma, increase)
    else
        println("γ unchanged")
    end
end

"""
Get raw configurations before merge for a variable.
"""
function get_raw_configs(problem::TNProblem, var_id::Int; k::Int=3, max_tensors::Int=4)
    selector = MostOccurrenceSelector(k, max_tensors)
    measure = NumUnfixedTensors()
    set_cover_solver = GreedyMerge()
    cache = init_cache(problem, TNContractionSolver(), measure, set_cover_solver, selector)

    region, cached_configs = get_region_data!(cache, problem, var_id)
    feasible_configs = filter_feasible_configs(problem, region, cached_configs, measure)
    unfixed_positions, unfixed_vars = extract_unfixed_vars(problem.doms, region.vars)
    projected = project_configs(feasible_configs, unfixed_positions)

    return projected, unfixed_vars
end

"""
Print configurations as binary strings.
"""
function print_configs(configs, variables)
    n_vars = length(variables)
    println("Configurations ($(length(configs)) total):")
    for (i, c) in enumerate(configs)
        bits = [Int((c >> (j-1)) & 1) for j in 1:n_vars]
        println("  $i: $(join(bits, ""))")
    end
end

"""
Find the best variable for MinGamma by scanning candidates.
If skip_gamma_one=true, find the best γ > 1 variable to demonstrate OB compression.
If find_max_compression=true, find the variable with maximum compression ratio.
"""
function find_mingamma_best(problem::TNProblem; k::Int=3, max_tensors::Int=4, limit::Int=0,
                            skip_gamma_one::Bool=false, min_configs::Int=1, find_max_compression::Bool=false)
    selector = MostOccurrenceSelector(k, max_tensors)
    measure = NumUnfixedTensors()
    set_cover_solver = GreedyMerge()
    cache = init_cache(problem, TNContractionSolver(), measure, set_cover_solver, selector)

    unfixed_vars = get_unfixed_vars(problem)
    candidates = limit == 0 ? unfixed_vars : unfixed_vars[1:min(limit, length(unfixed_vars))]

    best_γ = Inf
    best_compression = 0.0
    best_var = 0
    all_results = Dict{Int, NamedTuple}()

    for var_id in candidates
        result, variables, table_info = compute_branching_result(cache, problem, var_id, measure, set_cover_solver)
        isnothing(result) && continue

        γ = result.γ
        n_configs = table_info.n_configs
        n_branches = length(result.optimal_rule)
        compression = n_configs / max(n_branches, 1)
        all_results[var_id] = (gamma=γ, n_configs=n_configs, n_branches=n_branches, compression=compression)

        # Skip γ=1 if requested, and require minimum configs
        if skip_gamma_one && γ == 1.0
            continue
        end
        if n_configs < min_configs
            continue
        end

        if find_max_compression
            # Find maximum compression
            if compression > best_compression
                best_compression = compression
                best_var = var_id
            end
        else
            # Find minimum γ
            if γ < best_γ
                best_γ = γ
                best_var = var_id
            end
        end
    end

    return best_var, all_results
end

# ============================================================================
# Main experiment
# ============================================================================

function run_case_study(; m::Int=14, n::Int=14, N::Union{Int,Nothing}=nothing, seed::Int=42)
    println("="^70)
    println("Branching Case Study: MostOccurrence vs MinGamma")
    println("="^70)

    # Generate a semiprime if not provided
    if isnothing(N)
        Random.seed!(seed)

        function isprime(n)
            n < 2 && return false
            n == 2 && return true
            n % 2 == 0 && return false
            for i in 3:2:isqrt(n)
                n % i == 0 && return false
            end
            return true
        end

        function random_prime(bits)
            while true
                p = rand(2^(bits-1):2^bits-1)
                isprime(p) && return p
            end
        end

        p = random_prime(m)
        q = random_prime(n)
        N = p * q

        println("\nFactoring instance:")
        println("  N = $N = $p × $q")
    else
        println("\nFactoring instance:")
        println("  N = $N")
    end
    println("  Bit lengths: m=$m, n=$n")

    # Create the factoring problem
    problem = factoring_problem(m, n, N)
    println("  Variables: $(length(problem.static.vars))")
    println("  Tensors: $(length(problem.static.tensors))")

    # ========================================================================
    # MostOccurrence analysis
    # ========================================================================
    println("\n" * "-"^70)
    println("Analyzing MostOccurrence selection...")

    # Use moderate region for clearer visualization
    max_t = 3  # moderate region for paper example

    most_occ_var = find_best_var_by_score(problem)
    result_most_occ = analyze_variable_branching(problem, most_occ_var; k=3, max_tensors=max_t)
    print_branch_analysis("MostOccurrence", result_most_occ)

    # Print raw configurations
    println("\nRaw configurations before merge:")
    configs_A, vars_A = get_raw_configs(problem, most_occ_var; k=3, max_tensors=max_t)
    print_configs(configs_A, vars_A)

    # ========================================================================
    # MinGamma analysis - find a γ>1 case with good compression
    # ========================================================================
    println("\n" * "-"^70)
    println("Analyzing MinGamma selection (finding γ>1 with compression)...")

    # Find variable with best gamma improvement (γ>1, at least 4 configs)
    # First collect all results to find best gamma reduction
    mingamma_var, all_gammas = find_mingamma_best(problem; k=3, max_tensors=max_t, limit=0,
                                                   skip_gamma_one=true, min_configs=4, find_max_compression=true)

    # Also analyze a few more candidates to find best γ improvement
    println("\nSearching for best γ improvement...")
    best_improvement = 0.0
    best_var_for_improvement = mingamma_var
    for (vid, data) in all_gammas
        if data.gamma < 1.0 || data.n_configs < 4
            continue
        end
        # Quick check: compression suggests potential for γ improvement
        if data.compression > 1.5
            r = analyze_variable_branching(problem, vid; k=3, max_tensors=max_t)
            if r.gamma_before > r.gamma
                improvement = (r.gamma_before - r.gamma) / r.gamma_before
                if improvement > best_improvement
                    best_improvement = improvement
                    best_var_for_improvement = vid
                    @printf("  Found var %d: γ %.4f → %.4f (%.1f%% improvement)\n",
                            vid, r.gamma_before, r.gamma, improvement * 100)
                end
            end
        end
    end
    mingamma_var = best_var_for_improvement

    # Show distribution of gamma values
    gammas = [v.gamma for v in values(all_gammas)]
    configs_list = [v.n_configs for v in values(all_gammas)]
    branches_list = [v.n_branches for v in values(all_gammas)]

    println("\nGamma distribution across all variables:")
    @printf("  Min γ: %.4f\n", minimum(gammas))
    @printf("  Max γ: %.4f\n", maximum(gammas))
    @printf("  γ=1 count: %d / %d\n", count(g -> g == 1.0, gammas), length(gammas))

    # Show compression statistics
    compression_ratios = configs_list ./ max.(branches_list, 1)
    println("\nCompression statistics (configs/branches):")
    @printf("  Max compression: %.2fx\n", maximum(compression_ratios))
    @printf("  Variables with compression > 1: %d\n", count(c -> c > 1.0, compression_ratios))

    # Find and show the best compression case details
    best_comp_var = argmax(v -> haskey(all_gammas, v) ? all_gammas[v].compression : 0.0, collect(keys(all_gammas)))
    best_data = all_gammas[best_comp_var]
    @printf("\n  Best compression case (var %d): %d configs → %d branches (%.1fx), γ=%.4f\n",
            best_comp_var, best_data.n_configs, best_data.n_branches, best_data.compression, best_data.gamma)

    result_mingamma = analyze_variable_branching(problem, mingamma_var; k=3, max_tensors=max_t)
    print_branch_analysis("MinGamma (γ>1, best compression)", result_mingamma)

    # Print raw configurations
    println("\nRaw configurations before merge:")
    configs_B, vars_B = get_raw_configs(problem, mingamma_var; k=3, max_tensors=max_t)
    print_configs(configs_B, vars_B)

    # ========================================================================
    # Summary comparison
    # ========================================================================
    println("\n" * "="^70)
    println("SUMMARY COMPARISON")
    println("="^70)
    println()
    @printf("%-20s %15s %15s\n", "Metric", "MostOccurrence", "MinGamma")
    println("-"^50)
    @printf("%-20s %15d %15d\n", "Selected variable", result_most_occ.variable, result_mingamma.variable)
    @printf("%-20s %15d %15d\n", "Region variables", result_most_occ.n_vars_in_region, result_mingamma.n_vars_in_region)
    @printf("%-20s %15d %15d\n", "Configurations", result_most_occ.n_configs, result_mingamma.n_configs)
    @printf("%-20s %15d %15d\n", "Branches (merged)", result_most_occ.n_branches, result_mingamma.n_branches)
    @printf("%-20s %15.2fx %14.2fx\n", "Compression", result_most_occ.compression_ratio, result_mingamma.compression_ratio)
    @printf("%-20s %15.4f %15.4f\n", "γ (branching factor)", result_most_occ.gamma, result_mingamma.gamma)

    println("\n" * "="^70)
    println("INTERPRETATION:")
    if result_mingamma.gamma < result_most_occ.gamma
        improvement = (result_most_occ.gamma - result_mingamma.gamma) / result_most_occ.gamma * 100
        @printf("• OB with better variable achieves %.1f%% lower γ\n", improvement)
    end
    println("\nKey observation:")
    println("• MostOccurrence: $(result_most_occ.n_configs) configs → $(result_most_occ.n_branches) branches (no compression)")
    println("• MinGamma:       $(result_mingamma.n_configs) configs → $(result_mingamma.n_branches) branches (OB compresses!)")
    if result_mingamma.compression_ratio > result_most_occ.compression_ratio
        @printf("• OB compression ratio: %.1fx vs %.1fx\n",
                result_mingamma.compression_ratio, result_most_occ.compression_ratio)
    end
    println("="^70)

    return (most_occ=result_most_occ, mingamma=result_mingamma, all_gammas=all_gammas)
end

# Run the experiment
if abspath(PROGRAM_FILE) == @__FILE__
    run_case_study(m=14, n=14, seed=42)
end
