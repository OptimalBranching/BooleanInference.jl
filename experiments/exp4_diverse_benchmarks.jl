"""
Experiment 4: Diverse Problem Benchmarks

Evaluate BooleanInference on diverse problem types beyond factoring:
- Random 3-CNF SAT (phase transition instances)
- Multiplier verification miters (SAT: buggy, UNSAT: equivalent)
- Circuit SAT (ISCAS85 benchmarks)

This experiment tests whether optimal branching generalizes across problem structures.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "benchmarks"))

using BooleanInferenceBenchmarks
using BooleanInferenceBenchmarks: solve, load, Solvers
using BooleanInference: MostOccurrenceSelector, MinGammaSelector, NumUnfixedTensors, NoReducer
using Printf
using CSV
using DataFrames
using JSON3
using Dates
using Statistics

# ============================================================================
# System Information
# ============================================================================

function get_system_info()
    return Dict{String,Any}(
        "julia_version" => string(VERSION),
        "os" => string(Sys.KERNEL),
        "machine" => Sys.MACHINE,
        "cpu_threads" => Sys.CPU_THREADS,
        "total_memory_gb" => round(Sys.total_memory() / 2^30, digits=2),
        "hostname" => gethostname()
    )
end

function get_experiment_metadata(experiment_name::String; description::String="")
    ts = now()
    return Dict{String,Any}(
        "experiment_name" => experiment_name,
        "description" => description,
        "timestamp" => Dates.format(ts, "yyyy-mm-dd HH:MM:SS"),
        "timestamp_compact" => Dates.format(ts, "yyyymmdd_HHMMSS"),
        "system_info" => get_system_info()
    )
end

# ============================================================================
# Result structures
# ============================================================================

struct BenchmarkResult
    problem_type::String
    instance::String
    solver::String
    status::String          # SAT, UNSAT, TIMEOUT, ERROR
    time::Float64
    branches::Int           # branching nodes (BI) or decisions (CDCL)
    conflicts::Int          # unsat leaves (BI) or conflicts (CDCL)
    extra::Dict{String,Any} # solver-specific metrics
end

# ============================================================================
# Solver runners
# ============================================================================

function run_bi_solver(problem_type::String, instance; timeout::Float64=300.0)
    solver = Solvers.BI(
        selector = MinGammaSelector(3, 3, 0),
        measure = NumUnfixedTensors(),
        show_stats = false,
        reducer = NoReducer()
    )

    t0 = time()
    try
        result = solve(instance; solver=solver)
        elapsed = min(time() - t0, timeout)

        status = string(result.status)
        branches = result.branches
        conflicts = result.conflicts

        extra = Dict{String,Any}(
            "gamma_one" => result.gamma_one,
            "avg_vars_per_branch" => result.avg_vars_per_branch
        )

        return BenchmarkResult(
            problem_type, instance.name, "BI",
            status, elapsed, branches, conflicts, extra
        )
    catch e
        elapsed = time() - t0
        return BenchmarkResult(
            problem_type, instance.name, "BI",
            "ERROR", elapsed, 0, 0, Dict{String,Any}("error" => string(e))
        )
    end
end

function run_kissat_solver(problem_type::String, instance; timeout::Float64=300.0)
    solver = Solvers.Kissat(timeout=timeout, quiet=false)  # quiet=false to capture statistics

    t0 = time()
    try
        result = solve(instance; solver=solver)
        elapsed = min(time() - t0, timeout)

        status = string(result.status)
        decisions = result.branches
        conflicts = result.conflicts

        extra = Dict{String,Any}()

        return BenchmarkResult(
            problem_type, instance.name, "Kissat",
            status, elapsed, decisions, conflicts, extra
        )
    catch e
        elapsed = time() - t0
        return BenchmarkResult(
            problem_type, instance.name, "Kissat",
            "ERROR", elapsed, 0, 0, Dict{String,Any}("error" => string(e))
        )
    end
end

# ============================================================================
# Problem loaders
# ============================================================================

function load_3cnf_instances(data_dir::String; n::Int=150, ratios::Vector{Int}=[600, 630, 645, 675], max_per_ratio::Int=5)
    instances = []
    for r in ratios
        dir = joinpath(data_dir, "3CNF", "random", "n=$n", "$n-$r")
        !isdir(dir) && continue

        files = filter(f -> endswith(f, ".cnf"), readdir(dir))
        for (i, f) in enumerate(files)
            i > max_per_ratio && break
            inst = load(joinpath(dir, f))
            push!(instances, inst)
        end
    end
    return instances
end

function load_multver_instances(data_dir::String; max_instances::Int=10)
    instances = []
    multver_dir = joinpath(data_dir, "multver")
    !isdir(multver_dir) && return instances

    files = filter(f -> endswith(f, ".cnf"), readdir(multver_dir))
    for (i, f) in enumerate(files)
        i > max_instances && break
        inst = load(joinpath(multver_dir, f))
        push!(instances, inst)
    end
    return instances
end

function load_circuit_instances(data_dir::String; max_instances::Int=5)
    instances = []
    iscas_dir = joinpath(data_dir, "iscas85")
    !isdir(iscas_dir) && return instances

    # Look for .v or .aag files
    for ext in [".v", ".aag"]
        files = filter(f -> endswith(f, ext), readdir(iscas_dir))
        for (i, f) in enumerate(files)
            length(instances) >= max_instances && break
            try
                inst = load(joinpath(iscas_dir, f))
                push!(instances, inst)
            catch e
                @warn "Failed to load $f: $e"
            end
        end
    end
    return instances
end

# ============================================================================
# Main experiment
# ============================================================================

function run_diverse_benchmark(;
    timeout::Float64 = 300.0,
    output_dir::String = joinpath(@__DIR__, "results"),
    data_dir::String = joinpath(@__DIR__, "..", "benchmarks", "data")
)
    println("="^80)
    println("Experiment 4: Diverse Problem Benchmarks")
    println("="^80)

    metadata = get_experiment_metadata(
        "exp4_diverse_benchmarks",
        description="Evaluate BI on diverse problem types: 3-CNF, multiplier verification, circuit SAT"
    )
    timestamp = metadata["timestamp_compact"]

    all_results = BenchmarkResult[]

    # ========================================================================
    # 1. Random 3-CNF SAT (phase transition)
    # ========================================================================
    println("\n[1/3] Random 3-CNF SAT instances")
    println("-"^40)

    cnf_instances = load_3cnf_instances(data_dir; n=150, ratios=[600, 630, 645, 675], max_per_ratio=5)
    println("Loaded $(length(cnf_instances)) 3-CNF instances")

    for (i, inst) in enumerate(cnf_instances)
        println("  [$i/$(length(cnf_instances))] $(inst.name)")

        # BI solver
        print("    BI... ")
        flush(stdout)
        r = run_bi_solver("3-CNF", inst; timeout=timeout)
        push!(all_results, r)
        @printf("%s, %.3fs, branches=%d\n", r.status, r.time, r.branches)

        # Kissat
        print("    Kissat... ")
        flush(stdout)
        r = run_kissat_solver("3-CNF", inst; timeout=timeout)
        push!(all_results, r)
        @printf("%s, %.3fs, decisions=%d\n", r.status, r.time, r.branches)
    end

    # ========================================================================
    # 2. Multiplier Verification
    # ========================================================================
    println("\n[2/3] Multiplier Verification instances")
    println("-"^40)

    multver_instances = load_multver_instances(data_dir; max_instances=10)
    println("Loaded $(length(multver_instances)) multiplier verification instances")

    for (i, inst) in enumerate(multver_instances)
        println("  [$i/$(length(multver_instances))] $(inst.name)")

        # BI solver
        print("    BI... ")
        flush(stdout)
        r = run_bi_solver("MultVer", inst; timeout=timeout)
        push!(all_results, r)
        @printf("%s, %.3fs, branches=%d\n", r.status, r.time, r.branches)

        # Kissat
        print("    Kissat... ")
        flush(stdout)
        r = run_kissat_solver("MultVer", inst; timeout=timeout)
        push!(all_results, r)
        @printf("%s, %.3fs, decisions=%d\n", r.status, r.time, r.branches)
    end


    # ========================================================================
    # Save results
    # ========================================================================
    mkpath(output_dir)
    base_name = "exp4_diverse_$(timestamp)"

    # CSV output
    df = DataFrame(
        problem_type = [r.problem_type for r in all_results],
        instance = [r.instance for r in all_results],
        solver = [r.solver for r in all_results],
        status = [r.status for r in all_results],
        time = [r.time for r in all_results],
        branches = [r.branches for r in all_results],
        conflicts = [r.conflicts for r in all_results]
    )
    csv_file = joinpath(output_dir, "$(base_name).csv")
    CSV.write(csv_file, df)
    println("\nResults saved to: $csv_file")

    # JSON with full metadata
    json_output = Dict{String,Any}(
        "metadata" => metadata,
        "results" => [
            Dict{String,Any}(
                "problem_type" => r.problem_type,
                "instance" => r.instance,
                "solver" => r.solver,
                "status" => r.status,
                "time" => r.time,
                "branches" => r.branches,
                "conflicts" => r.conflicts,
                "extra" => r.extra
            ) for r in all_results
        ]
    )
    json_file = joinpath(output_dir, "$(base_name).json")
    open(json_file, "w") do f
        JSON3.pretty(f, json_output)
    end
    println("Full results saved to: $json_file")

    # Print summary
    print_summary(all_results)

    return all_results
end

function extract_ratio(instance_name::String)
    # Extract ratio from instance name like "3sat_n150_r600_1.cnf"
    m = match(r"r(\d+)", instance_name)
    return isnothing(m) ? "unknown" : m.captures[1]
end

function print_summary(results::Vector{BenchmarkResult})
    println("\n" * "="^80)
    println("Summary by Problem Type, Ratio, and Solver")
    println("="^80)

    for ptype in unique(r.problem_type for r in results)
        ptype_results = filter(r -> r.problem_type == ptype, results)

        # Get unique ratios
        ratios = unique(extract_ratio(r.instance) for r in ptype_results)
        sort!(ratios)

        for ratio in ratios
            ratio_results = filter(r -> extract_ratio(r.instance) == ratio, ptype_results)
            println("\n$ptype (ratio=$ratio):")
            println("-"^80)
            @printf("%-10s %6s %10s %12s %12s %8s\n",
                "Solver", "Solved", "Med Time", "Med Branch", "Med Confl", "Timeouts")
            println("-"^80)

            for solver in unique(r.solver for r in ratio_results)
                solver_results = filter(r -> r.solver == solver, ratio_results)
                solved = count(r -> r.status in ["SAT", "UNSAT"], solver_results)
                timeouts = count(r -> r.status == "TIMEOUT", solver_results)

                solved_results = filter(r -> r.status in ["SAT", "UNSAT"], solver_results)
                med_time = isempty(solved_results) ? NaN : median([r.time for r in solved_results])
                med_branches = isempty(solved_results) ? NaN : median([r.branches for r in solved_results])
                med_conflicts = isempty(solved_results) ? NaN : median([r.conflicts for r in solved_results])

                @printf("%-10s %6d %10.3fs %12.1f %12.1f %8d\n",
                    solver, solved, med_time, med_branches, med_conflicts, timeouts)
            end
        end
    end
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_diverse_benchmark(timeout=300.0)
end
