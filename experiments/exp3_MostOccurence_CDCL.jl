"""
Experiment 3: BI (MostOccurrenceSelector) vs CDCL Solvers Comparison

Compare BooleanInference solver with CDCL solvers (Kissat, CryptoMiniSat)
on factoring problems.

Metrics recorded:
- Running time
- For BI: children_explored (branches), avg_vars_per_branch, unsat_leaves (conflicts)
- For CDCL: decisions, conflicts
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "benchmarks"))

using BooleanInferenceBenchmarks
using BooleanInference
using OptimalBranchingCore
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
# Data structures for results
# ============================================================================

struct BISolverResult
    instance::String
    n::Int
    m::Int
    N::BigInt
    solver::String
    found::Bool
    time::Float64
    branches::Int           # children_explored
    avg_vars_per_branch::Float64
    conflicts::Int          # unsat_leaves
end

struct CDCLSolverResult
    instance::String
    n::Int
    m::Int
    N::BigInt
    solver::String
    found::Bool
    time::Float64
    decisions::Int
    conflicts::Int
end

# ============================================================================
# Experiment runner
# ============================================================================

function run_bi_solver(inst::FactoringInstance)
    bsconfig = BranchingStrategy(
        table_solver = TNContractionSolver(),
        selector = MostOccurrenceSelector(3, 4),
        measure = NumUnfixedTensors(),
        set_cover_solver = GreedyMerge()
    )
    reducer = NoReducer()

    t0 = time()
    a, b, stats = solve_factoring(inst.n, inst.m, Int(inst.N);
        bsconfig=bsconfig, reducer=reducer, show_stats=false)
    elapsed = time() - t0

    found = !isnothing(a) && !isnothing(b)
    branches = stats.children_explored
    avg_vars = stats.avg_vars_per_branch
    conflicts = stats.unsat_leaves

    return BISolverResult(
        "$(inst.m)x$(inst.n)_$(inst.N)",
        inst.n, inst.m, inst.N,
        "BI(MostOcc(3,4)+NumUnfixedTensors+NoReducer)",
        found, elapsed, branches, avg_vars, conflicts
    )
end

function run_kissat_solver(inst::FactoringInstance)
    solver = Solvers.Kissat(timeout=300.0, quiet=false)  # quiet=false to get statistics

    t0 = time()
    p, q, result = solve_instance(FactoringProblem, inst, solver)
    elapsed = time() - t0

    found = !isnothing(p) && !isnothing(q)
    decisions = something(result.decisions, 0)
    conflicts = something(result.conflicts, 0)

    return CDCLSolverResult(
        "$(inst.m)x$(inst.n)_$(inst.N)",
        inst.n, inst.m, inst.N,
        "Kissat",
        found, elapsed, decisions, conflicts
    )
end

function run_cryptominisat_solver(inst::FactoringInstance)
    solver = Solvers.CryptoMiniSat(timeout=300.0, quiet=false)  # quiet=false to get statistics

    t0 = time()
    p, q, result = solve_instance(FactoringProblem, inst, solver)
    elapsed = time() - t0

    found = !isnothing(p) && !isnothing(q)
    decisions = something(result.decisions, 0)
    conflicts = something(result.conflicts, 0)

    return CDCLSolverResult(
        "$(inst.m)x$(inst.n)_$(inst.N)",
        inst.n, inst.m, inst.N,
        "CryptoMiniSat",
        found, elapsed, decisions, conflicts
    )
end

# ============================================================================
# Main experiment
# ============================================================================

function run_experiment(;
    bit_sizes::Vector{Tuple{Int,Int}} = [(14, 14), (16, 16), (18, 18)],
    per_config::Int = 10,
    output_dir::String = joinpath(@__DIR__, "results")
)
    println("="^80)
    println("Experiment 3: BI vs CDCL Comparison")
    println("="^80)
    println("Bit sizes: ", bit_sizes)
    println("Instances per config: ", per_config)
    println()

    # Create experiment metadata
    metadata = get_experiment_metadata(
        "exp3_bi_vs_cdcl",
        description="Compare BI (MostOccurrenceSelector) with CDCL solvers (Kissat, CryptoMiniSat) on factoring problems."
    )
    metadata["parameters"] = Dict{String,Any}(
        "bit_sizes" => bit_sizes,
        "per_config" => per_config,
        "bi_config" => "MostOccurrenceSelector(3,4) + NumUnfixedTensors + NoReducer",
        "cdcl_solvers" => ["Kissat", "CryptoMiniSat"]
    )
    timestamp = metadata["timestamp_compact"]

    # Generate or load instances
    data_dir = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring")
    mkpath(data_dir)

    instances = FactoringInstance[]

    for (m, n) in bit_sizes
        data_file = joinpath(data_dir, "numbers_$(m)x$(n).txt")
        if isfile(data_file)
            println("Loading instances from $data_file")
            open(data_file, "r") do io
                for line in eachline(io)
                    parts = split(strip(line))
                    # Format: m n N p q
                    length(parts) >= 5 || continue
                    file_m = parse(Int, parts[1])
                    file_n = parse(Int, parts[2])
                    N = parse(BigInt, parts[3])
                    p = parse(BigInt, parts[4])
                    q = parse(BigInt, parts[5])
                    push!(instances, FactoringInstance(file_m, file_n, N; p=p, q=q))
                    length(filter(i -> i.m == m && i.n == n, instances)) >= per_config && break
                end
            end
        else
            println("Generating instances for $(m)x$(n)")
            configs = [FactoringConfig(m, n)]
            paths = generate_factoring_datasets(configs; per_config=per_config, include_solution=true, force_regenerate=false)
            # Load the generated instances
            if !isempty(paths)
                open(paths[1], "r") do io
                    for line in eachline(io)
                        parts = split(strip(line))
                        # Format: m n N p q
                        length(parts) >= 5 || continue
                        file_m = parse(Int, parts[1])
                        file_n = parse(Int, parts[2])
                        N = parse(BigInt, parts[3])
                        p = parse(BigInt, parts[4])
                        q = parse(BigInt, parts[5])
                        push!(instances, FactoringInstance(file_m, file_n, N; p=p, q=q))
                    end
                end
            end
        end
    end

    println("Total instances: ", length(instances))

    # Warm-up
    println("\nWarming up (compiling code)...")
    if !isempty(instances)
        warmup_inst = instances[1]
        try
            run_bi_solver(warmup_inst)
            run_kissat_solver(warmup_inst)
            run_cryptominisat_solver(warmup_inst)
            println("Warm-up completed\n")
        catch e
            @warn "Warm-up failed (not critical)" exception=e
        end
    end

    # Run experiments
    bi_results = BISolverResult[]
    cdcl_results = CDCLSolverResult[]

    for (idx, inst) in enumerate(instances)
        println("[$(idx)/$(length(instances))] Instance: $(inst.m)x$(inst.n), N=$(inst.N)")

        # BI solver
        print("  - BI... ")
        flush(stdout)
        try
            r = run_bi_solver(inst)
            push!(bi_results, r)
            @printf("found=%s, time=%.3fs, branches=%d, avg_vars=%.2f, conflicts=%d\n",
                r.found, r.time, r.branches, r.avg_vars_per_branch, r.conflicts)
        catch e
            println("FAILED: $e")
        end

        # Kissat
        print("  - Kissat... ")
        flush(stdout)
        try
            r = run_kissat_solver(inst)
            push!(cdcl_results, r)
            @printf("found=%s, time=%.3fs, decisions=%d, conflicts=%d\n",
                r.found, r.time, r.decisions, r.conflicts)
        catch e
            println("FAILED: $e")
        end

        # CryptoMiniSat
        print("  - CryptoMiniSat... ")
        flush(stdout)
        try
            r = run_cryptominisat_solver(inst)
            push!(cdcl_results, r)
            @printf("found=%s, time=%.3fs, decisions=%d, conflicts=%d\n",
                r.found, r.time, r.decisions, r.conflicts)
        catch e
            println("FAILED: $e")
        end

        println()
    end

    # Save results (with timestamp to avoid overwriting)
    mkpath(output_dir)
    base_name = "exp3_bi_vs_cdcl_$(timestamp)"

    # Save BI results (CSV)
    bi_output_file = joinpath(output_dir, "$(base_name)_bi.csv")
    bi_df = DataFrame(
        instance = [r.instance for r in bi_results],
        n = [r.n for r in bi_results],
        m = [r.m for r in bi_results],
        N = [string(r.N) for r in bi_results],
        solver = [r.solver for r in bi_results],
        found = [r.found for r in bi_results],
        time = [r.time for r in bi_results],
        branches = [r.branches for r in bi_results],
        avg_vars_per_branch = [r.avg_vars_per_branch for r in bi_results],
        conflicts = [r.conflicts for r in bi_results]
    )
    CSV.write(bi_output_file, bi_df)
    println("\nBI results saved to: $bi_output_file")

    # Save CDCL results (CSV)
    cdcl_output_file = joinpath(output_dir, "$(base_name)_cdcl.csv")
    cdcl_df = DataFrame(
        instance = [r.instance for r in cdcl_results],
        n = [r.n for r in cdcl_results],
        m = [r.m for r in cdcl_results],
        N = [string(r.N) for r in cdcl_results],
        solver = [r.solver for r in cdcl_results],
        found = [r.found for r in cdcl_results],
        time = [r.time for r in cdcl_results],
        decisions = [r.decisions for r in cdcl_results],
        conflicts = [r.conflicts for r in cdcl_results]
    )
    CSV.write(cdcl_output_file, cdcl_df)
    println("CDCL results saved to: $cdcl_output_file")

    # Save complete JSON with metadata
    json_output = Dict{String,Any}(
        "metadata" => metadata,
        "bi_results" => [
            Dict{String,Any}(
                "instance" => r.instance, "n" => r.n, "m" => r.m, "N" => string(r.N),
                "solver" => r.solver, "found" => r.found, "time" => r.time,
                "branches" => r.branches, "avg_vars_per_branch" => r.avg_vars_per_branch,
                "conflicts" => r.conflicts
            ) for r in bi_results
        ],
        "cdcl_results" => [
            Dict{String,Any}(
                "instance" => r.instance, "n" => r.n, "m" => r.m, "N" => string(r.N),
                "solver" => r.solver, "found" => r.found, "time" => r.time,
                "decisions" => r.decisions, "conflicts" => r.conflicts
            ) for r in cdcl_results
        ]
    )
    json_file = joinpath(output_dir, "$(base_name).json")
    open(json_file, "w") do f
        JSON3.pretty(f, json_output)
    end
    println("Complete results saved to: $json_file")

    # Print summary table
    print_summary(bi_results, cdcl_results, bit_sizes)

    return (bi=bi_results, cdcl=cdcl_results)
end

function print_summary(bi_results::Vector{BISolverResult}, cdcl_results::Vector{CDCLSolverResult}, bit_sizes)
    println("\n" * "="^80)
    println("Summary by solver and bit size")
    println("="^80)

    for (m, n) in bit_sizes
        bi_size = filter(r -> r.m == m && r.n == n, bi_results)
        cdcl_size = filter(r -> r.m == m && r.n == n, cdcl_results)

        (isempty(bi_size) && isempty(cdcl_size)) && continue

        println("\n$(m)x$(n) bits:")
        println("-"^90)
        @printf("%-45s %8s %10s %12s %10s\n", "Solver", "Med Time", "Branches", "Med Vars", "Conflicts")
        println("-"^90)

        # BI results
        if !isempty(bi_size)
            med_time = median([r.time for r in bi_size])
            med_branches = median([r.branches for r in bi_size])
            med_vars = median([r.avg_vars_per_branch for r in bi_size])
            med_conflicts = median([r.conflicts for r in bi_size])
            @printf("%-45s %8.3fs %10.1f %12.2f %10.1f\n",
                "BI(MostOcc+NumUnfixedTensors+NoReducer)", med_time, med_branches, med_vars, med_conflicts)
        end

        # CDCL results (decisions instead of branches, no avg_vars)
        println("-"^90)
        @printf("%-45s %8s %10s %12s %10s\n", "Solver", "Med Time", "Decisions", "-", "Conflicts")
        println("-"^90)

        for solver in unique(r.solver for r in cdcl_size)
            solver_results = filter(r -> r.solver == solver, cdcl_size)
            med_time = median([r.time for r in solver_results])
            med_decisions = median([r.decisions for r in solver_results])
            med_conflicts = median([r.conflicts for r in solver_results])
            @printf("%-45s %8.3fs %10.1f %12s %10.1f\n", solver, med_time, med_decisions, "-", med_conflicts)
        end
    end
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_experiment(
        bit_sizes = [(16,16),(18, 18),(20, 20)],
        per_config = 10
    )
end
