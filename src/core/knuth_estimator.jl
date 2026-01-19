# ============================================================================
# Knuth Tree Size Estimator (Corrected Implementation)
# ============================================================================
#
# Background (Lemma 8.4.9):
# A perfect measure μ must satisfy: μ(F) ∝ log(Real_Tree_Size(F))
#
# Knuth's algorithm estimates tree size via Monte Carlo random walks:
# 1. Start from root, randomly dive to a leaf
# 2. Track the probability P of the path taken
# 3. Estimate = 1/P
# 4. Average over many walks
#
# TWO VERSIONS:
# 1. Uniform Sampling: prob = 1/k for k branches (baseline)
# 2. Importance Sampling: prob ∝ γ^(-Δρ) based on measure (test measure quality)
#
# Key insight: If measure is perfect, importance sampling should have 
# MUCH lower variance than uniform sampling.
# ============================================================================

using Statistics: mean, std, var

"""
    KnuthEstimatorResult

Result of Knuth tree size estimation.
"""
struct KnuthEstimatorResult
    # Primary results
    log10_mean_size::Float64      # log₁₀(mean tree size) - main result
    log10_std::Float64            # Standard deviation in log₁₀ space
    log_variance::Float64         # Variance of log₁₀(estimates) - KEY METRIC

    # Sample statistics
    num_samples::Int
    avg_path_length::Float64
    avg_gamma::Float64            # Average γ observed
    gamma_cv::Float64             # Coefficient of variation of γ

    # Raw data
    log_estimates::Vector{Float64}  # log₁₀ of individual walk estimates
    path_gammas::Vector{Vector{Float64}}  # γ values along each path
end

function Base.show(io::IO, r::KnuthEstimatorResult)
    println(io, "KnuthEstimatorResult:")
    println(io, "  Samples: $(r.num_samples)")
    println(io, "  Estimated tree size: 10^$(round(r.log10_mean_size, digits=2))")
    println(io, "  Log₁₀ variance: $(round(r.log_variance, digits=4))  ← KEY METRIC (lower is better)")
    println(io, "  Avg γ: $(round(r.avg_gamma, digits=4)), γ CV: $(round(r.gamma_cv * 100, digits=2))%")
    println(io, "  Avg path length: $(round(r.avg_path_length, digits=1)) decisions")
end

# ============================================================================
# VERSION 1: Uniform Sampling (Baseline)
# ============================================================================
# 
# At each node with k branches, pick uniformly: prob = 1/k
# Estimate = ∏ k_i = 2^(Σ log₂ k_i)
#
# This is the CONTROL. High variance expected for unbalanced trees.
# ============================================================================

"""
    knuth_uniform(problem, config; num_samples=100, max_depth=10000)

Knuth estimator with UNIFORM sampling (baseline).
At each node, pick each branch with equal probability 1/k.

High variance is expected - this is the control to compare against.
"""
function knuth_uniform(
    problem::TNProblem,
    config::BranchingStrategy;
    num_samples::Int=100,
    max_depth::Int=10000,
    verbose::Bool=false
)
    return knuth_estimate_core(
        problem, config, :uniform;
        num_samples=num_samples, max_depth=max_depth, verbose=verbose
    )
end

# ============================================================================
# VERSION 2: Importance Sampling (Tests Measure Quality)
# ============================================================================
# 
# At each node, use the branching vector (Δρ values) to compute probabilities:
#   prob_i ∝ γ^(-Δρ_i / T)  where γ is the branching factor, T is temperature
#
# Temperature controls the "sharpness" of the distribution:
#   T = 1: Standard importance sampling
#   T → ∞: Approaches uniform sampling (ignore measure)
#   T → 0: Greedy (always pick largest Δρ)
#
# If the measure is perfect:
#   - prob_i reflects true subtree size
#   - All random walks give similar estimates
#   - Variance → 0
# ============================================================================

"""
    knuth_importance(problem, config; num_samples=100, temperature=1.0, max_depth=10000)

Knuth estimator with IMPORTANCE sampling based on the measure.
Probability of each branch is proportional to γ^(-Δρ/T).

Arguments:
- `temperature`: Controls distribution sharpness (default=1.0)
  - T=1: Standard importance sampling
  - T>1: More uniform (less trust in measure)
  - T<1: More greedy (more trust in measure)

If measure satisfies log-linear condition, variance should be VERY LOW.
"""
function knuth_importance(
    problem::TNProblem,
    config::BranchingStrategy;
    num_samples::Int=100,
    temperature::Float64=1.0,
    max_depth::Int=10000,
    verbose::Bool=false
)
    return knuth_estimate_core(
        problem, config, :importance;
        num_samples=num_samples, max_depth=max_depth,
        temperature=temperature, verbose=verbose
    )
end

# ============================================================================
# Core Implementation
# ============================================================================

function knuth_estimate_core(
    problem::TNProblem,
    config::BranchingStrategy,
    sampling_mode::Symbol;  # :uniform or :importance
    num_samples::Int=100,
    max_depth::Int=10000,
    temperature::Float64=1.0,
    verbose::Bool=false
)
    log_estimates = Float64[]  # log₁₀ of each estimate
    path_lengths = Int[]
    path_gammas = Vector{Vector{Float64}}()

    # Initialize cache once for all samples
    cache = init_cache(problem, config.table_solver, config.measure, config.set_cover_solver, config.selector)

    for sample_idx in 1:num_samples
        log_est, path_length, gammas = single_knuth_dive(
            problem, config, cache, sampling_mode, max_depth,
            temperature, verbose && sample_idx <= 3
        )

        push!(log_estimates, log_est)
        push!(path_lengths, path_length)
        push!(path_gammas, gammas)

        if verbose && sample_idx % 20 == 0
            @info "Knuth sampling" mode = sampling_mode sample = sample_idx log10_estimate = round(log_est, digits=2)
        end
    end

    # Compute statistics
    # Key: Average in LINEAR space, then convert to log
    # Use LogSumExp trick: log(mean(10^x)) = log(sum(10^x)/n) = logsumexp(x) - log(n)
    log10_mean = logsumexp10(log_estimates) - log10(num_samples)

    # Variance of log estimates - this is the KEY METRIC
    log_var = var(log_estimates)
    log_std = std(log_estimates)

    # Gamma statistics
    all_gammas = vcat(path_gammas...)
    avg_gamma = isempty(all_gammas) ? 1.0 : mean(all_gammas)
    gamma_cv = isempty(all_gammas) ? 0.0 : std(all_gammas) / mean(all_gammas)

    avg_path = mean(path_lengths)

    return KnuthEstimatorResult(
        log10_mean, log_std, log_var,
        num_samples, avg_path, avg_gamma, gamma_cv,
        log_estimates, path_gammas
    )
end

"""
    logsumexp10(log_values)

Compute log₁₀(Σ 10^xᵢ) in a numerically stable way.
"""
function logsumexp10(log_values::Vector{Float64})
    isempty(log_values) && return -Inf
    max_val = maximum(log_values)
    isinf(max_val) && return max_val
    return max_val + log10(sum(10.0^(x - max_val) for x in log_values))
end

"""
    single_knuth_dive(problem, config, cache, sampling_mode, max_depth, temperature, verbose)

Perform a single random dive from root to leaf.

Returns:
- log₁₀(estimate): The log of 1/P where P is the path probability
- path_length: Number of decisions made
- gammas: γ values at each decision point
"""
function single_knuth_dive(
    problem::TNProblem,
    config::BranchingStrategy,
    cache::RegionCache,
    sampling_mode::Symbol,
    max_depth::Int,
    temperature::Float64,
    verbose::Bool
)
    # Create a copy of the problem state
    current_doms = copy(problem.doms)

    log_prob = 0.0  # log₁₀(P) - accumulate log probability
    depth = 0
    gammas = Float64[]

    while depth < max_depth
        # Check if solved
        n_unfixed = count(!is_fixed(d) for d in current_doms)
        if n_unfixed == 0
            break
        end

        # Create temporary problem view with current doms
        temp_problem = TNProblem(
            problem.static,
            current_doms,
            BranchingStats(),
            problem.buffer
        )

        # Reset the branching cache for clean computation
        empty!(temp_problem.buffer.branching_cache)

        # Get branching options
        result = findbest(
            cache, temp_problem, config.measure,
            config.set_cover_solver, config.selector, depth
        )

        clauses, variables, gamma = result

        # If no branching possible (solved or contradiction), stop
        if isnothing(clauses) || isempty(clauses)
            break
        end

        num_branches = length(clauses)
        gamma_val = gamma === nothing ? Float64(num_branches) : gamma
        push!(gammas, gamma_val)

        # Skip single-branch "decisions" (forced propagation)
        if num_branches == 1
            # Apply the only option
            apply_branch!(current_doms, problem, clauses[1], variables)
            if has_contradiction(current_doms)
                break
            end
            continue  # Don't count as a decision
        end

        # Compute branch probabilities based on sampling mode
        if sampling_mode == :uniform
            # Uniform: each branch has probability 1/k
            probs = fill(1.0 / num_branches, num_branches)
        else
            # Importance sampling: prob_i ∝ γ^(-Δρ_i / T)
            probs = compute_importance_probs(temp_problem, config.measure, clauses, variables, gamma_val, temperature)
        end

        # Randomly select a branch according to probabilities
        branch_idx = weighted_random_choice(probs)
        chosen_prob = probs[branch_idx]

        # Update log probability: log(P) = Σ log(p_i)
        log_prob += log10(chosen_prob)

        # Apply the selected clause
        apply_branch!(current_doms, problem, clauses[branch_idx], variables)

        # Check for contradiction
        if has_contradiction(current_doms)
            break
        end

        depth += 1

        if verbose && depth <= 5
            @info "Dive step" depth = depth gamma = round(gamma, digits=4) branches = num_branches prob = round(chosen_prob, digits=4) log_estimate = round(-log_prob, digits=2)
        end
    end

    # Estimate = 1/P  =>  log(Estimate) = -log(P)
    log_estimate = -log_prob

    return log_estimate, depth, gammas
end

"""
    compute_importance_probs(problem, measure, clauses, variables, gamma, temperature)

Compute importance sampling probabilities for each branch.
prob_i ∝ γ^(-Δρ_i / T) where Δρ_i is the measure reduction for branch i.

Temperature T controls distribution sharpness:
- T = 1: Standard importance sampling
- T > 1: Flatter distribution (more uniform)
- T < 1: Sharper distribution (more greedy)
"""
function compute_importance_probs(
    problem::TNProblem,
    measure::AbstractMeasure,
    clauses::Vector{Clause{UInt64}},
    variables::Vector{Int},
    gamma::Float64,
    temperature::Float64=1.0
)
    n = length(clauses)
    current_measure = OptimalBranchingCore.measure(problem, measure)

    # Compute Δρ for each branch
    delta_rhos = Float64[]
    for clause in clauses
        new_doms = copy(problem.doms)
        apply_clause_to_doms!(new_doms, clause, variables)

        # Propagate to get true measure reduction
        propagated = propagate(
            problem.static,
            new_doms,
            get_touched_tensors(problem.static, variables),
            problem.buffer
        )

        if has_contradiction(propagated)
            # This branch leads to contradiction - give it minimal probability
            push!(delta_rhos, current_measure)  # Maximum reduction
        else
            new_measure = measure_core(problem.static, propagated, measure)
            delta_rho = current_measure - new_measure
            push!(delta_rhos, max(0.1, delta_rho))  # Avoid zero/negative
        end
    end

    # prob_i ∝ γ^(-Δρ_i / T)
    # In log space: log(prob_i) ∝ -Δρ_i * log(γ) / T
    log_gamma = log(max(1.001, gamma))  # Avoid log(1) = 0
    T = max(0.001, temperature)  # Avoid division by zero
    log_weights = [-dr * log_gamma / T for dr in delta_rhos]

    # Normalize using softmax-like computation
    max_lw = maximum(log_weights)
    weights = [exp(lw - max_lw) for lw in log_weights]
    total = sum(weights)

    probs = weights ./ total
    return probs
end

"""
    weighted_random_choice(probs)

Choose an index according to probability distribution.
"""
function weighted_random_choice(probs::Vector{Float64})
    r = rand()
    cumsum = 0.0
    for (i, p) in enumerate(probs)
        cumsum += p
        if r <= cumsum
            return i
        end
    end
    return length(probs)  # Fallback
end

"""
    apply_branch!(doms, problem, clause, variables)

Apply a branching clause and propagate.
"""
function apply_branch!(
    doms::Vector{DomainMask},
    problem::TNProblem,
    clause::Clause{UInt64},
    variables::Vector{Int}
)
    apply_clause_to_doms!(doms, clause, variables)

    new_doms = propagate(
        problem.static,
        doms,
        get_touched_tensors(problem.static, variables),
        problem.buffer
    )

    copy!(doms, new_doms)
end

"""
    apply_clause_to_doms!(doms, clause, variables)

Apply clause assignments to domain mask.
"""
function apply_clause_to_doms!(doms::Vector{DomainMask}, clause::Clause{UInt64}, variables::Vector{Int})
    mask = clause.mask
    val = clause.val
    @inbounds for (i, var_id) in enumerate(variables)
        if (mask >> (i - 1)) & 1 == 1
            bit = (val >> (i - 1)) & 1
            doms[var_id] = bit == 1 ? DM_1 : DM_0
        end
    end
end

"""
    get_touched_tensors(static, variables)

Get list of tensors that need propagation after fixing variables.
"""
function get_touched_tensors(static::ConstraintNetwork, variables::Vector{Int})
    touched = Set{Int}()
    @inbounds for var_id in variables
        for tensor_id in static.v2t[var_id]
            push!(touched, tensor_id)
        end
    end
    return collect(touched)
end

# ============================================================================
# Comparative Measure Evaluation
# ============================================================================

"""
    compare_measures_knuth(problem; measures, num_samples=100)

Compare different measures using both uniform and importance sampling.

The KEY INSIGHT:
- Uniform sampling variance = baseline (expected to be high)
- Importance sampling variance = test measure quality
- If importance variance << uniform variance → measure is good!
"""
function compare_measures_knuth(
    problem::TNProblem;
    measures::Vector{<:AbstractMeasure}=[NumUnfixedVars(), NumUnfixedTensors()],
    selector::AbstractSelector=MostOccurrenceSelector(3, 4),
    num_samples::Int=100,
    verbose::Bool=true
)
    results = Dict{String,NamedTuple{(:uniform, :importance),Tuple{KnuthEstimatorResult,KnuthEstimatorResult}}}()

    for m in measures
        name = string(typeof(m))
        verbose && @info "Evaluating measure: $name"

        config = BranchingStrategy(
            table_solver=TNContractionSolver(),
            selector=selector,
            measure=m,
            set_cover_solver=GreedyMerge()
        )

        # Run both versions
        uniform_result = knuth_uniform(problem, config; num_samples=num_samples, verbose=false)
        importance_result = knuth_importance(problem, config; num_samples=num_samples, verbose=false)

        results[name] = (uniform=uniform_result, importance=importance_result)

        if verbose
            println("\n$name:")
            println("  Tree size estimate: 10^$(round(importance_result.log10_mean_size, digits=2))")
            println("  ┌─ Uniform Sampling (baseline):")
            println("  │  Log variance: $(round(uniform_result.log_variance, digits=4))")
            println("  │  Avg γ: $(round(uniform_result.avg_gamma, digits=4))")
            println("  └─ Importance Sampling (tests measure):")
            println("     Log variance: $(round(importance_result.log_variance, digits=4))  ← KEY")
            println("     Avg γ: $(round(importance_result.avg_gamma, digits=4))")

            # Variance reduction ratio
            if uniform_result.log_variance > 0
                ratio = importance_result.log_variance / uniform_result.log_variance
                println("     Variance ratio: $(round(ratio, digits=3)) (lower is better)")
            end
        end
    end

    # Print summary
    if verbose
        println("\n" * "="^70)
        println("SUMMARY")
        println("="^70)
        println("Lower importance sampling variance = Better measure")
        println("")

        sorted = sort(collect(results), by=x -> x[2].importance.log_variance)
        for (i, (name, res)) in enumerate(sorted)
            marker = i == 1 ? "★ BEST" : ""
            uni_var = round(res.uniform.log_variance, digits=4)
            imp_var = round(res.importance.log_variance, digits=4)
            println("  $(rpad(name, 25)) uniform=$(uni_var)  importance=$(imp_var)  $marker")
        end
    end

    return results
end

# Keep old API for compatibility
function knuth_estimate(args...; kwargs...)
    return knuth_uniform(args...; kwargs...)
end

function compare_measures(args...; kwargs...)
    return compare_measures_knuth(args...; kwargs...)
end

function analyze_gamma_distribution(result::KnuthEstimatorResult)
    all_gammas = vcat(result.path_gammas...)

    if isempty(all_gammas)
        println("No gamma values recorded")
        return nothing
    end

    println("Gamma Distribution Analysis:")
    println("  Total γ observations: $(length(all_gammas))")
    println("  Mean γ: $(round(mean(all_gammas), digits=4))")
    println("  Std γ: $(round(std(all_gammas), digits=4))")
    println("  Min γ: $(round(minimum(all_gammas), digits=4))")
    println("  Max γ: $(round(maximum(all_gammas), digits=4))")
    println("  CV: $(round(std(all_gammas)/mean(all_gammas) * 100, digits=2))%")

    cv = std(all_gammas) / mean(all_gammas)
    if cv < 0.1
        println("  ✓ γ is relatively stable (CV < 10%)")
    elseif cv < 0.3
        println("  ⚠ γ shows moderate variation (10% < CV < 30%)")
    else
        println("  ✗ γ shows high variation (CV > 30%)")
    end

    return (mean=mean(all_gammas), std=std(all_gammas), cv=cv)
end
