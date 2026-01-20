"""
Direct comparison of GreedyMerge vs IPSolver on constructed BranchingTables.
More direct way to compare set cover solvers without running full problems.
"""

using OptimalBranchingCore
using OptimalBranchingCore: BranchingTable, GreedyMerge, IPSolver, optimal_branching_rule
using OptimalBranchingCore: AbstractMeasure, AbstractProblem, Clause
using Statistics
using Printf
using HiGHS
using Random
using JSON3
using Dates

Random.seed!(42)

# Simple measure: count bits in mask
struct BitCountMeasure <: AbstractMeasure end

# Simple problem
struct MockProblem <: AbstractProblem
    n::Int
end

# size_reduction with explicit type to avoid ambiguity
function OptimalBranchingCore.size_reduction(p::MockProblem, ::BitCountMeasure, clause::Clause{T}, variables::Vector) where T
    return count_ones(clause.mask)
end

"""
Generate a random branching table with n_vars variables and n_configs configurations.
"""
function random_branching_table(n_vars::Int, n_configs::Int)
    max_val = (1 << n_vars) - 1
    configs = unique(rand(0:max_val, n_configs * 2))
    configs = configs[1:min(length(configs), n_configs)]
    table = [[UInt64(c)] for c in configs]
    return BranchingTable(n_vars, table)
end

function run_direct_comparison(;
    test_cases = [
        (n_vars=4, n_configs=8, n_tables=100),
        (n_vars=5, n_configs=12, n_tables=100),
        (n_vars=5, n_configs=20, n_tables=100),
        (n_vars=6, n_configs=16, n_tables=100),
        (n_vars=6, n_configs=32, n_tables=100),
        (n_vars=7, n_configs=24, n_tables=100),
        (n_vars=7, n_configs=48, n_tables=100),
        (n_vars=8, n_configs=32, n_tables=100),
        (n_vars=8, n_configs=64, n_tables=100),
        (n_vars=8, n_configs=128, n_tables=100),
    ]
)
    println("="^70)
    println("Direct Comparison: GreedyMerge vs IPSolver on BranchingTables")
    println("="^70)

    measure = BitCountMeasure()
    all_results = []

    for (n_vars, n_configs, n_tables) in test_cases
        println("\n" * "-"^70)
        @printf("Testing: %d vars, ~%d configs, %d tables\n", n_vars, n_configs, n_tables)
        println("-"^70)

        greedy_gammas = Float64[]
        ip_gammas = Float64[]
        greedy_times = Float64[]
        ip_times = Float64[]

        variables = collect(1:n_vars)
        problem = MockProblem(n_vars)

        for i in 1:n_tables
            table = random_branching_table(n_vars, n_configs)

            # Skip trivial tables
            length(table.table) < 2 && continue

            t_greedy = @elapsed result_greedy = optimal_branching_rule(table, variables, problem, measure, GreedyMerge())
            t_ip = @elapsed result_ip = optimal_branching_rule(table, variables, problem, measure, IPSolver(optimizer=HiGHS.Optimizer, verbose=false))

            # Skip if either failed
            (result_greedy.γ == Inf || result_ip.γ == Inf) && continue

            push!(greedy_gammas, result_greedy.γ)
            push!(ip_gammas, result_ip.γ)
            push!(greedy_times, t_greedy * 1000)
            push!(ip_times, t_ip * 1000)
        end

        isempty(greedy_gammas) && continue

        diff = greedy_gammas .- ip_gammas
        n_greedy_larger = sum(diff .> 1e-9)
        n_ip_larger = sum(diff .< -1e-9)
        n_equal = sum(abs.(diff) .<= 1e-9)

        @printf("  Valid tables: %d\n", length(greedy_gammas))
        @printf("  Greedy γ > IP γ: %d (%.1f%%)\n", n_greedy_larger, n_greedy_larger/length(diff)*100)
        @printf("  IP γ > Greedy γ: %d (%.1f%%)\n", n_ip_larger, n_ip_larger/length(diff)*100)
        @printf("  Equal:           %d (%.1f%%)\n", n_equal, n_equal/length(diff)*100)
        @printf("  Mean diff:       %+.6f\n", mean(diff))
        @printf("  Max diff:        %+.6f\n", maximum(diff))
        @printf("  Greedy time:     %.3f ms\n", mean(greedy_times))
        @printf("  IP time:         %.3f ms\n", mean(ip_times))
        @printf("  Speedup:         %.1fx\n", mean(ip_times)/mean(greedy_times))

        push!(all_results, (
            n_vars=n_vars, n_configs=n_configs,
            n_tables=length(greedy_gammas),
            pct_equal=n_equal/length(diff)*100,
            pct_greedy_larger=n_greedy_larger/length(diff)*100,
            mean_diff=mean(diff),
            max_diff=maximum(diff),
            speedup=mean(ip_times)/mean(greedy_times)
        ))
    end

    println("\n" * "="^70)
    println("SUMMARY")
    println("="^70)
    @printf("\n%-12s | %6s | %8s | %10s | %10s | %8s\n",
            "Config", "Tables", "Equal %", "Greedy>IP", "Mean Diff", "Speedup")
    println("-"^70)
    for r in all_results
        @printf("%dv x %3dc   | %6d | %7.1f%% | %9.1f%% | %+10.6f | %7.1fx\n",
                r.n_vars, r.n_configs, r.n_tables, r.pct_equal, r.pct_greedy_larger, r.mean_diff, r.speedup)
    end

    # Save results to files
    results_dir = joinpath(@__DIR__, "results")
    mkpath(results_dir)

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")

    # Save JSON
    json_file = joinpath(results_dir, "greedymerge_vs_ipsolver_$(timestamp).json")
    json_data = [
        Dict(
            "n_vars" => r.n_vars,
            "n_configs" => r.n_configs,
            "n_tables" => r.n_tables,
            "pct_equal" => r.pct_equal,
            "pct_greedy_larger" => r.pct_greedy_larger,
            "pct_ip_larger" => 100.0 - r.pct_equal - r.pct_greedy_larger,
            "mean_diff" => r.mean_diff,
            "max_diff" => r.max_diff,
            "speedup" => r.speedup
        )
        for r in all_results
    ]
    open(json_file, "w") do io
        JSON3.pretty(io, json_data)
    end
    println("\nSaved JSON: $json_file")

    # Save CSV
    csv_file = joinpath(results_dir, "greedymerge_vs_ipsolver_$(timestamp).csv")
    open(csv_file, "w") do io
        println(io, "n_vars,n_configs,n_tables,pct_equal,pct_greedy_larger,pct_ip_larger,mean_diff,max_diff,speedup")
        for r in all_results
            pct_ip_larger = 100.0 - r.pct_equal - r.pct_greedy_larger
            println(io, "$(r.n_vars),$(r.n_configs),$(r.n_tables),$(r.pct_equal),$(r.pct_greedy_larger),$(pct_ip_larger),$(r.mean_diff),$(r.max_diff),$(r.speedup)")
        end
    end
    println("Saved CSV: $csv_file")

    return all_results
end

# Run
results = run_direct_comparison()
