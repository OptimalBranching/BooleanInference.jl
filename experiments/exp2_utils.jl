"""
Experiment 2 Utilities: Compare BI (direct) vs BI-CnC

This module provides utilities for comparing:
1. BI (direct): Direct solving with BooleanInference (TN-based branching)
2. BI-CnC: TN-based cubing + CDCL (kissat) for each cube

This shows whether the CnC hybrid approach helps compared to pure TN-based solving.

Key feature: ALL cubes are evaluated (doesn't stop on first SAT) to collect complete statistics.
"""

using BooleanInference
using BooleanInference: setup_from_sat, Cube, CubeResult
using OptimalBranchingCore
using OptimalBranchingCore: BranchingStrategy, GreedyMerge
using ProblemReductions: reduceto, CircuitSAT, Factoring
using DataFrames
using CSV
using JSON3
using Statistics
using Printf
using Dates

# ============================================================================
# System Information (shared with exp1_utils)
# ============================================================================

function get_system_info()
    return Dict{String,Any}(
        "julia_version" => string(VERSION),
        "os" => string(Sys.KERNEL),
        "machine" => Sys.MACHINE,
        "cpu_threads" => Sys.CPU_THREADS,
        "total_memory_gb" => round(Sys.total_memory() / 2^30, digits=2),
        "word_size" => Sys.WORD_SIZE,
        "hostname" => gethostname()
    )
end

function get_experiment_metadata(experiment_name::String; description::String="")
    ts = now()
    return Dict{String,Any}(
        "experiment_name" => experiment_name,
        "description" => description,
        "timestamp" => Dates.format(ts, "yyyy-mm-dd HH:MM:SS"),
        "timestamp_utc" => Dates.format(now(UTC), "yyyy-mm-dd HH:MM:SS"),
        "timestamp_compact" => Dates.format(ts, "yyyymmdd_HHMMSS"),
        "system_info" => get_system_info()
    )
end

function get_output_path(output_dir::String, experiment_name::String; use_timestamp::Bool=true)
    mkpath(output_dir)
    if use_timestamp
        ts = Dates.format(now(), "yyyymmdd_HHMMSS")
        return joinpath(output_dir, "$(experiment_name)_$(ts)")
    else
        return joinpath(output_dir, experiment_name)
    end
end

# ============================================================================
# Result Types
# ============================================================================

"""
    CubeStats

Statistics for a single cube solve.
"""
struct CubeStats
    cube_idx::Int
    n_literals::Int
    status::Symbol
    solve_time::Float64
    decisions::Int
    conflicts::Int
end

"""
    CnCExperimentResult

Complete result for a CnC experiment run.
"""
struct CnCExperimentResult
    instance_name::String
    n::Int
    m::Int
    N::BigInt
    solver_name::String

    # Cubing phase stats
    n_cubes::Int
    n_refuted::Int
    cubing_time::Float64
    avg_cube_literals::Float64

    # CDCL solve phase stats (evaluating ALL cubes)
    n_sat_cubes::Int
    n_unsat_cubes::Int
    total_solve_time::Float64      # Sum of all cube solve times (serial time)
    wall_clock_solve_time::Float64 # Actual elapsed time (parallel time)
    total_decisions::Int
    total_conflicts::Int

    # Per-cube stats
    per_cube_stats::Vector{CubeStats}
end

# ============================================================================
# BI (Direct): Direct BooleanInference solving
# ============================================================================

"""
    BIDirectResult

Result from direct BI solving.
"""
struct BIDirectResult
    instance_name::String
    n::Int
    m::Int
    N::BigInt
    solver_name::String

    # Solving stats
    found::Bool
    solve_time::Float64
    total_nodes::Int
    branching_nodes::Int
    reduction_nodes::Int
    terminal_nodes::Int
    sat_leaves::Int
    unsat_leaves::Int
    avg_gamma::Float64
end

"""
    run_bi_direct_experiment(n, m, N, bsconfig, reducer) -> BIDirectResult

Run direct BI solving experiment.
"""
function run_bi_direct_experiment(
    n::Int, m::Int, N::BigInt,
    bsconfig::BranchingStrategy,
    reducer::OptimalBranchingCore.AbstractReducer
)
    instance_name = "$(n)x$(m)_$(N)"

    solve_time = @elapsed begin
        a, b, stats = solve_factoring(n, m, Int(N); bsconfig=bsconfig, reducer=reducer, show_stats=false)
    end

    found = !isnothing(a) && !isnothing(b) && a * b == N

    return BIDirectResult(
        instance_name,
        n, m, N,
        "BI-Direct",
        found,
        solve_time,
        stats.total_nodes,
        stats.branching_nodes,
        stats.reduction_nodes,
        stats.terminal_nodes,
        stats.sat_leaves,
        stats.unsat_leaves,
        stats.avg_gamma
    )
end

# ============================================================================
# BI-CnC: BooleanInference Cube-and-Conquer
# ============================================================================

"""
    solve_all_cubes_bi(cubes, cnf; nvars, parallel=true) -> (per_cube_stats, summary)

Solve ALL cubes with CDCL (Kissat), collecting statistics for each.
Does NOT stop when SAT is found - evaluates all cubes.

If parallel=true, uses multithreading to solve cubes in parallel.
"""
function solve_all_cubes_bi(cubes::Vector{Cube}, cnf::Vector{Vector{Int}}; nvars::Int, parallel::Bool=true)
    # Filter non-refuted cubes
    active_cubes = [(idx, cube) for (idx, cube) in enumerate(cubes) if !cube.is_refuted]

    if isempty(active_cubes)
        return CubeStats[], (n_sat=0, n_unsat=0, total_time=0.0, wall_time=0.0,
                            total_decisions=0, total_conflicts=0)
    end

    # Solve cubes (in parallel if requested)
    wall_time = @elapsed begin
        if parallel && Threads.nthreads() > 1
            # Parallel solving
            per_cube_stats = Vector{CubeStats}(undef, length(active_cubes))
            Threads.@threads for i in 1:length(active_cubes)
                idx, cube = active_cubes[i]
                cube_cnf = [cnf; [[lit] for lit in cube.literals]]

                cube_time = @elapsed begin
                    status, _, _, cdcl_stats = solve_and_mine(cube_cnf; nvars=nvars)
                end

                per_cube_stats[i] = CubeStats(
                    idx,
                    length(cube.literals),
                    status,
                    cube_time,
                    cdcl_stats.decisions,
                    cdcl_stats.conflicts
                )
            end
        else
            # Serial solving
            per_cube_stats = CubeStats[]
            for (idx, cube) in active_cubes
                cube_cnf = [cnf; [[lit] for lit in cube.literals]]

                cube_time = @elapsed begin
                    status, _, _, cdcl_stats = solve_and_mine(cube_cnf; nvars=nvars)
                end

                push!(per_cube_stats, CubeStats(
                    idx,
                    length(cube.literals),
                    status,
                    cube_time,
                    cdcl_stats.decisions,
                    cdcl_stats.conflicts
                ))
            end
        end
    end

    # Aggregate statistics
    n_sat = count(cs -> cs.status == :sat, per_cube_stats)
    n_unsat = count(cs -> cs.status == :unsat, per_cube_stats)
    total_time = sum(cs -> cs.solve_time, per_cube_stats)
    total_decisions = sum(cs -> cs.decisions, per_cube_stats)
    total_conflicts = sum(cs -> cs.conflicts, per_cube_stats)

    summary = (
        n_sat = n_sat,
        n_unsat = n_unsat,
        total_time = total_time,
        wall_time = wall_time,
        total_decisions = total_decisions,
        total_conflicts = total_conflicts
    )

    return per_cube_stats, summary
end

"""
    run_bi_cnc_experiment(n, m, N, cutoff, bsconfig, reducer; parallel=true) -> CnCExperimentResult

Run BI-CnC experiment, evaluating ALL cubes.
If parallel=true, uses multithreading to solve cubes in parallel.
"""
function run_bi_cnc_experiment(
    n::Int, m::Int, N::BigInt,
    cutoff::AbstractCutoffStrategy,
    bsconfig::BranchingStrategy,
    reducer::OptimalBranchingCore.AbstractReducer;
    parallel::Bool=true
)
    instance_name = "$(n)x$(m)_$(N)"

    # Setup problem
    reduction = reduceto(CircuitSAT, Factoring(n, m, N))
    circuit_sat = CircuitSAT(reduction.circuit.circuit; use_constraints=true)
    q_vars = collect(reduction.q)
    p_vars = collect(reduction.p)

    tn_problem = setup_from_sat(circuit_sat)
    target_vars = [q_vars; p_vars]

    # Generate cubes
    cubing_time = @elapsed begin
        cube_result = generate_cubes!(tn_problem, bsconfig, reducer, cutoff; target_vars)
    end

    avg_lits = isempty(cube_result.cubes) ? 0.0 :
               sum(c -> length(c.literals), cube_result.cubes) / length(cube_result.cubes)

    @printf("cubes=%d (refuted=%d), cubing_time=%.2fs, avg_lits=%.1f\n",
        cube_result.n_cubes, cube_result.n_refuted, cubing_time, avg_lits)
    print("    Solving cubes... ")
    flush(stdout)

    # Convert to CNF for CDCL
    cnf = tn_to_cnf(tn_problem.static)
    nvars = num_tn_vars(tn_problem.static)

    # Solve ALL cubes
    per_cube_stats, summary = solve_all_cubes_bi(cube_result.cubes, cnf; nvars=nvars, parallel=parallel)

    avg_dec = length(per_cube_stats) > 0 ? summary.total_decisions / length(per_cube_stats) : 0.0
    if parallel && Threads.nthreads() > 1
        @printf("done. wall_time=%.2fs (serial=%.2fs), avg_dec=%.1f\n",
            summary.wall_time, summary.total_time, avg_dec)
    else
        @printf("done. solve_time=%.2fs, avg_dec=%.1f\n",
            summary.total_time, avg_dec)
    end

    return CnCExperimentResult(
        instance_name,
        n, m, N,
        "BI-CnC",
        cube_result.n_cubes,
        cube_result.n_refuted,
        cubing_time,
        avg_lits,
        summary.n_sat,
        summary.n_unsat,
        summary.total_time,
        summary.wall_time,
        summary.total_decisions,
        summary.total_conflicts,
        per_cube_stats
    )
end

# ============================================================================
# march_cu-CnC: External Cube-and-Conquer
# ============================================================================

"""
    run_march_cnc_experiment(n, m, N; march_cu_path, kissat_path, cutoff_nvars=0, parallel=true) -> CnCExperimentResult

Run march_cu-CnC experiment, evaluating ALL cubes.
If parallel=true, uses multithreading to solve cubes in parallel.
"""
function run_march_cnc_experiment(
    n::Int, m::Int, N::BigInt;
    march_cu_path::String,
    kissat_path::String,
    cutoff_nvars::Int = 0,
    parallel::Bool = true
)
    instance_name = "$(n)x$(m)_$(N)"

    # Create CNF from factoring problem
    fproblem = Factoring(n, m, N)
    reduction = reduceto(CircuitSAT, fproblem)
    cnf, symbols = circuit_to_cnf(reduction.circuit.circuit)

    nvars = length(symbols)
    for clause in cnf
        for lit in clause
            nvars = max(nvars, abs(Int(lit)))
        end
    end

    # Write CNF to temp file
    cnf_path = tempname() * ".cnf"
    cubes_file = tempname() * ".cubes"

    open(cnf_path, "w") do io
        println(io, "p cnf $nvars $(length(cnf))")
        for clause in cnf
            for lit in clause
                print(io, lit, " ")
            end
            println(io, "0")
        end
    end

    # Build march_cu command
    march_cmd = [march_cu_path, cnf_path, "-o", cubes_file]
    cutoff_nvars > 0 && append!(march_cmd, ["-n", string(cutoff_nvars)])

    # Generate cubes
    cubing_time = @elapsed begin
        stdout_pipe, stderr_pipe = Pipe(), Pipe()
        proc = run(pipeline(Cmd(march_cmd), stdout=stdout_pipe, stderr=stderr_pipe), wait=false)
        close(stdout_pipe.in)
        close(stderr_pipe.in)
        march_output = read(stdout_pipe, String)
        wait(proc)
    end

    # Check if UNSAT during cube generation
    if occursin("UNSATISFIABLE", march_output)
        rm(cnf_path, force=true)
        rm(cubes_file, force=true)
        return CnCExperimentResult(
            instance_name, n, m, N, "march_cu-CnC",
            0, 0, cubing_time, 0.0,
            0, 0, 0.0, 0.0, 0, 0, CubeStats[]
        )
    end

    # Parse march_cu statistics
    cubes_match = match(r"c number of cubes (\d+), including (\d+) refuted", march_output)
    num_cubes = isnothing(cubes_match) ? 0 : parse(Int, cubes_match.captures[1])
    num_refuted = isnothing(cubes_match) ? 0 : parse(Int, cubes_match.captures[2])

    if !isfile(cubes_file) || num_cubes == 0
        rm(cnf_path, force=true)
        rm(cubes_file, force=true)
        return CnCExperimentResult(
            instance_name, n, m, N, "march_cu-CnC",
            num_cubes, num_refuted, cubing_time, 0.0,
            0, 0, 0.0, 0.0, 0, 0, CubeStats[]
        )
    end

    # Read cubes
    cube_lines = readlines(cubes_file)
    cnf_lines = readlines(cnf_path)

    # Parse all cube literals first
    cubes_data = []
    for cube_line in cube_lines
        isempty(strip(cube_line)) && continue
        startswith(cube_line, "a") || continue

        cube_lits = String[]
        for lit in split(cube_line)[2:end]
            lit = strip(lit)
            lit == "0" && break
            push!(cube_lits, lit)
        end
        isempty(cube_lits) && continue
        push!(cubes_data, cube_lits)
    end

    total_cube_vars = sum(length, cubes_data)

    # Count non-empty cubes
    @printf("cubes=%d (refuted=%d), cubing_time=%.2fs\n",
        num_cubes, num_refuted, cubing_time)
    print("    Solving cubes... ")
    flush(stdout)

    # Solve ALL cubes (in parallel or serial)
    wall_time = @elapsed begin
        if parallel && Threads.nthreads() > 1
            # Parallel solving
            per_cube_stats = Vector{Union{CubeStats,Nothing}}(undef, length(cubes_data))
            Threads.@threads for i in 1:length(cubes_data)
                cube_lits = cubes_data[i]

                # Create CNF with cube as unit clauses
                cube_cnf_path = tempname() * ".cnf"
                open(cube_cnf_path, "w") do io
                    for line in cnf_lines
                        if startswith(line, "p cnf")
                            parts = split(line)
                            nv = parse(Int, parts[3])
                            nc = parse(Int, parts[4]) + length(cube_lits)
                            println(io, "p cnf $nv $nc")
                        else
                            println(io, line)
                        end
                    end
                    for lit in cube_lits
                        println(io, "$lit 0")
                    end
                end

                # Run kissat (use ignorestatus because kissat returns 10 for SAT, 20 for UNSAT)
                # Use simple read() instead of pipeline for thread safety
                kissat_output = ""
                cube_time = @elapsed begin
                    kissat_output = read(ignorestatus(`$kissat_path $cube_cnf_path`), String)
                end

                rm(cube_cnf_path, force=true)

                # Parse result from output (exit codes: 10=SAT, 20=UNSAT)
                status = if occursin(r"(?m)^s\s+SATISFIABLE", kissat_output)
                    :sat
                elseif occursin(r"(?m)^s\s+UNSATISFIABLE", kissat_output)
                    :unsat
                else
                    :unknown
                end

                decisions_match = match(r"c\s+decisions:\s+(\d+)", kissat_output)
                decisions = isnothing(decisions_match) ? 0 : parse(Int, decisions_match.captures[1])

                conflicts_match = match(r"c\s+conflicts:\s+(\d+)", kissat_output)
                conflicts = isnothing(conflicts_match) ? 0 : parse(Int, conflicts_match.captures[1])

                per_cube_stats[i] = CubeStats(i, length(cube_lits), status, cube_time, decisions, conflicts)
            end
            per_cube_stats = Vector{CubeStats}(filter(!isnothing, per_cube_stats))
        else
            # Serial solving
            per_cube_stats = CubeStats[]
            for (cube_idx, cube_lits) in enumerate(cubes_data)
                # Create CNF with cube as unit clauses
                cube_cnf_path = tempname() * ".cnf"
                open(cube_cnf_path, "w") do io
                    for line in cnf_lines
                        if startswith(line, "p cnf")
                            parts = split(line)
                            nv = parse(Int, parts[3])
                            nc = parse(Int, parts[4]) + length(cube_lits)
                            println(io, "p cnf $nv $nc")
                        else
                            println(io, line)
                        end
                    end
                    for lit in cube_lits
                        println(io, "$lit 0")
                    end
                end

                # Run kissat (use ignorestatus because kissat returns 10 for SAT, 20 for UNSAT)
                kissat_output = ""
                cube_time = @elapsed begin
                    kissat_output = read(ignorestatus(`$kissat_path $cube_cnf_path`), String)
                end

                rm(cube_cnf_path, force=true)

                # Parse result from output (exit codes: 10=SAT, 20=UNSAT)
                status = if occursin(r"(?m)^s\s+SATISFIABLE", kissat_output)
                    :sat
                elseif occursin(r"(?m)^s\s+UNSATISFIABLE", kissat_output)
                    :unsat
                else
                    :unknown
                end

                decisions_match = match(r"c\s+decisions:\s+(\d+)", kissat_output)
                decisions = isnothing(decisions_match) ? 0 : parse(Int, decisions_match.captures[1])

                conflicts_match = match(r"c\s+conflicts:\s+(\d+)", kissat_output)
                conflicts = isnothing(conflicts_match) ? 0 : parse(Int, conflicts_match.captures[1])

                push!(per_cube_stats, CubeStats(cube_idx, length(cube_lits), status, cube_time, decisions, conflicts))
            end
        end
    end

    # Aggregate statistics
    n_sat = count(cs -> cs.status == :sat, per_cube_stats)
    n_unsat = count(cs -> cs.status == :unsat, per_cube_stats)
    total_solve_time = sum(cs -> cs.solve_time, per_cube_stats)
    total_decisions = sum(cs -> cs.decisions, per_cube_stats)
    total_conflicts = sum(cs -> cs.conflicts, per_cube_stats)

    avg_dec = length(per_cube_stats) > 0 ? total_decisions / length(per_cube_stats) : 0.0
    if parallel && Threads.nthreads() > 1
        @printf("done. wall_time=%.2fs (serial=%.2fs), avg_dec=%.1f\n",
            wall_time, total_solve_time, avg_dec)
    else
        @printf("done. solve_time=%.2fs, avg_dec=%.1f\n",
            total_solve_time, avg_dec)
    end

    rm(cnf_path, force=true)
    rm(cubes_file, force=true)

    avg_lits = (num_cubes - num_refuted) > 0 ? total_cube_vars / (num_cubes - num_refuted) : 0.0

    return CnCExperimentResult(
        instance_name,
        n, m, N,
        "march_cu-CnC",
        num_cubes,
        num_refuted,
        cubing_time,
        avg_lits,
        n_sat,
        n_unsat,
        total_solve_time,
        wall_time,
        total_decisions,
        total_conflicts,
        per_cube_stats
    )
end

# ============================================================================
# Data Loading
# ============================================================================

"""
    load_factoring_instances(file_path; max_instances=10)

Load factoring instances from a text file.
"""
function load_factoring_instances(file_path::String; max_instances::Int=10)
    instances = []
    open(file_path, "r") do f
        for (i, line) in enumerate(eachline(f))
            i > max_instances && break
            isempty(strip(line)) && continue

            parts = split(strip(line))
            length(parts) < 3 && continue

            n = parse(Int, parts[1])
            m = parse(Int, parts[2])
            N = parse(BigInt, parts[3])
            p = length(parts) >= 4 ? parse(BigInt, parts[4]) : BigInt(0)
            q = length(parts) >= 5 ? parse(BigInt, parts[5]) : BigInt(0)

            name = "$(n)x$(m)_$(N)"
            push!(instances, (n=n, m=m, N=N, p=p, q=q, name=name))
        end
    end
    return instances
end

# ============================================================================
# Data Export
# ============================================================================

"""
    results_to_dataframe(results)

Convert CnC experiment results to a summary DataFrame.
"""
function results_to_dataframe(results::Vector{CnCExperimentResult})
    return DataFrame([
        (
            instance = r.instance_name,
            n = r.n,
            m = r.m,
            N = r.N,
            solver = r.solver_name,
            n_cubes = r.n_cubes,
            n_refuted = r.n_refuted,
            cubing_time = r.cubing_time,
            avg_literals = r.avg_cube_literals,
            n_sat = r.n_sat_cubes,
            n_unsat = r.n_unsat_cubes,
            serial_solve_time = r.total_solve_time,
            wall_solve_time = r.wall_clock_solve_time,
            total_decisions = r.total_decisions,
            avg_decisions = length(r.per_cube_stats) > 0 ? r.total_decisions / length(r.per_cube_stats) : 0.0,
            total_conflicts = r.total_conflicts,
            avg_conflicts = length(r.per_cube_stats) > 0 ? r.total_conflicts / length(r.per_cube_stats) : 0.0,
            total_time_serial = r.cubing_time + r.total_solve_time,
            total_time_wall = r.cubing_time + r.wall_clock_solve_time,
            speedup = r.total_solve_time > 0 ? r.total_solve_time / r.wall_clock_solve_time : 1.0
        )
        for r in results
    ])
end

"""
    per_cube_to_dataframe(results)

Convert per-cube statistics to a DataFrame.
"""
function per_cube_to_dataframe(results::Vector{CnCExperimentResult})
    rows = []
    for r in results
        for cs in r.per_cube_stats
            push!(rows, (
                instance = r.instance_name,
                solver = r.solver_name,
                cube_idx = cs.cube_idx,
                n_literals = cs.n_literals,
                status = String(cs.status),
                solve_time = cs.solve_time,
                decisions = cs.decisions,
                conflicts = cs.conflicts
            ))
        end
    end
    return DataFrame(rows)
end

"""
    save_results(results, filepath)

Save results to CSV and JSON files with metadata.
"""
function save_results(results::Vector{CnCExperimentResult}, filepath::String;
                      metadata::Dict{String,Any}=Dict{String,Any}())
    # Summary CSV
    df = results_to_dataframe(results)
    CSV.write(filepath * "_summary.csv", df)

    # Per-cube CSV
    df_cubes = per_cube_to_dataframe(results)
    if !isempty(df_cubes)
        CSV.write(filepath * "_per_cube.csv", df_cubes)
    end

    # Full JSON with metadata
    results_data = [
        Dict{String,Any}(
            "instance" => r.instance_name,
            "n" => r.n,
            "m" => r.m,
            "N" => string(r.N),
            "solver" => r.solver_name,
            "n_cubes" => r.n_cubes,
            "n_refuted" => r.n_refuted,
            "cubing_time" => r.cubing_time,
            "avg_cube_literals" => r.avg_cube_literals,
            "n_sat_cubes" => r.n_sat_cubes,
            "n_unsat_cubes" => r.n_unsat_cubes,
            "serial_solve_time" => r.total_solve_time,
            "wall_solve_time" => r.wall_clock_solve_time,
            "total_decisions" => r.total_decisions,
            "total_conflicts" => r.total_conflicts,
            "per_cube_stats" => [
                Dict{String,Any}(
                    "cube_idx" => cs.cube_idx,
                    "n_literals" => cs.n_literals,
                    "status" => String(cs.status),
                    "solve_time" => cs.solve_time,
                    "decisions" => cs.decisions,
                    "conflicts" => cs.conflicts
                )
                for cs in r.per_cube_stats
            ]
        )
        for r in results
    ]

    json_output = Dict{String,Any}(
        "metadata" => isempty(metadata) ? get_experiment_metadata("exp2_cnc") : metadata,
        "results" => results_data,
        "summary" => Dict{String,Any}(
            "total_instances" => length(results),
            "solvers" => unique(r.solver_name for r in results)
        )
    )

    open(filepath * ".json", "w") do f
        JSON3.pretty(f, json_output)
    end

    println("Results saved to:")
    println("  - $(filepath)_summary.csv")
    !isempty(df_cubes) && println("  - $(filepath)_per_cube.csv")
    println("  - $(filepath).json")
end

"""
    print_summary_table(results)

Print a summary comparison table.
"""
function print_summary_table(results::Vector{CnCExperimentResult})
    df = results_to_dataframe(results)

    grouped = combine(DataFrames.groupby(df, :solver),
        :n_cubes => mean => :avg_cubes,
        :n_refuted => mean => :avg_refuted,
        :cubing_time => median => :median_cube_time,
        :wall_solve_time => median => :median_wall_solve_time,
        :total_time_wall => median => :median_total_wall_time,
        :speedup => mean => :avg_speedup,
        :avg_decisions => mean => :avg_decisions_per_cube,
        :avg_conflicts => mean => :avg_conflicts_per_cube,
        nrow => :n_instances
    )

    println("\n" * "="^120)
    println("CnC Comparison Summary (Wall Clock Times)")
    println("="^120)
    println(grouped)
    println("="^120)
end

# ============================================================================
# BI-Direct DataFrame conversion
# ============================================================================

"""
    bi_direct_to_dataframe(results)

Convert BI-Direct results to DataFrame.
"""
function bi_direct_to_dataframe(results::Vector{BIDirectResult})
    return DataFrame([
        (
            instance = r.instance_name,
            n = r.n,
            m = r.m,
            N = r.N,
            solver = r.solver_name,
            found = r.found,
            solve_time = r.solve_time,
            total_nodes = r.total_nodes,
            branching_nodes = r.branching_nodes,
            reduction_nodes = r.reduction_nodes,
            terminal_nodes = r.terminal_nodes,
            sat_leaves = r.sat_leaves,
            unsat_leaves = r.unsat_leaves,
            avg_gamma = r.avg_gamma
        )
        for r in results
    ])
end

"""
    save_bi_direct_results(results, filepath)

Save BI-Direct results to CSV.
"""
function save_bi_direct_results(results::Vector{BIDirectResult}, filepath::String)
    df = bi_direct_to_dataframe(results)
    CSV.write(filepath * "_bi_direct.csv", df)
    println("BI-Direct results saved to: $(filepath)_bi_direct.csv")
end

"""
    print_comparison_table(bi_direct_results, cnc_results)

Print side-by-side comparison of BI-Direct vs BI-CnC.
"""
function print_comparison_table(bi_direct_results::Vector{BIDirectResult}, cnc_results::Vector{CnCExperimentResult})
    println("\n" * "="^110)
    println("BI-Direct vs BI-CnC Comparison")
    println("="^110)

    # Group by instance for comparison
    for (i, bi_res) in enumerate(bi_direct_results)
        # Find matching CnC result
        cnc_res = findfirst(r -> r.instance_name == bi_res.instance_name && r.solver_name == "BI-CnC", cnc_results)

        println("\nInstance: $(bi_res.instance_name)")
        @printf("  BI-Direct:  time=%.2fs, terminal_nodes=%d, γ=%.3f\n",
            bi_res.solve_time, bi_res.terminal_nodes, bi_res.avg_gamma)

        if !isnothing(cnc_res)
            r = cnc_results[cnc_res]
            total_time = r.cubing_time + r.total_solve_time
            @printf("  BI-CnC:     time=%.2fs (cube=%.2fs + solve=%.2fs), cubes=%d, total_dec=%d\n",
                total_time, r.cubing_time, r.total_solve_time, r.n_cubes, r.total_decisions)

            speedup = bi_res.solve_time / total_time
            @printf("  Speedup:    %.2fx %s\n", abs(speedup), speedup > 1 ? "(CnC faster)" : "(Direct faster)")
        end
    end
    println("="^110)
end
