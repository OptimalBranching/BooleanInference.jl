"""
Experiment 6: Kissat Baseline for Factoring

Measure Kissat's performance on integer factorization instances.
This provides a baseline for comparing structure-aware methods.

Parameters:
- bit_lengths: List of bit lengths to test
- max_instances: Maximum instances per bit length
- timeout: Timeout per instance in seconds
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "benchmarks"))

using BooleanInferenceBenchmarks
using Printf
using CSV
using DataFrames
using Statistics
using Dates

struct KissatResult
    instance::String
    bit_length::Int
    N::BigInt
    found::Bool
    time::Float64
    decisions::Int
    conflicts::Int
    status::Symbol  # :solved, :timeout, :error
end

function run_kissat_baseline(;
    bit_lengths::Vector{Int} = [32, 36, 40],
    max_instances::Int = 10,
    timeout::Float64 = 300.0,
    output_dir::String = joinpath(@__DIR__, "results")
)
    println("="^70)
    println("Experiment 6: Kissat Baseline for Factoring")
    println("="^70)
    println("Bit lengths: ", bit_lengths)
    println("Max instances per bit length: ", max_instances)
    println("Timeout: ", timeout, "s")
    println()

    data_dir = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring")
    results = KissatResult[]
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")

    for bit_length in bit_lengths
        m = bit_length ÷ 2
        n = bit_length ÷ 2
        data_file = joinpath(data_dir, "numbers_$(m)x$(n).txt")

        if !isfile(data_file)
            @warn "Data file not found: $data_file"
            continue
        end

        # Load instances
        instances = FactoringInstance[]
        open(data_file, "r") do io
            for line in eachline(io)
                parts = split(strip(line))
                length(parts) >= 5 || continue
                file_m = parse(Int, parts[1])
                file_n = parse(Int, parts[2])
                N = parse(BigInt, parts[3])
                p = parse(BigInt, parts[4])
                q = parse(BigInt, parts[5])
                push!(instances, FactoringInstance(file_m, file_n, N; p=p, q=q))
                length(instances) >= max_instances && break
            end
        end

        println("\n[$bit_length-bit] Loaded $(length(instances)) instances")
        println("-"^50)

        for (idx, inst) in enumerate(instances)
            print("  [$(idx)/$(length(instances))] N=$(inst.N)... ")
            flush(stdout)

            solver = Solvers.Kissat(timeout=timeout, quiet=false)

            try
                t0 = time()
                p, q, result = solve_instance(FactoringProblem, inst, solver)
                elapsed = time() - t0

                found = !isnothing(p) && !isnothing(q)
                decisions = something(result.decisions, 0)
                conflicts = something(result.conflicts, 0)

                status = elapsed >= timeout ? :timeout : :solved

                push!(results, KissatResult(
                    "$(m)x$(n)_$(inst.N)",
                    bit_length,
                    inst.N,
                    found,
                    elapsed,
                    decisions,
                    conflicts,
                    status
                ))

                if status == :timeout
                    @printf("TIMEOUT (%.1fs)\n", elapsed)
                else
                    @printf("%.3fs, dec=%d, conf=%d\n", elapsed, decisions, conflicts)
                end
            catch e
                push!(results, KissatResult(
                    "$(m)x$(n)_$(inst.N)",
                    bit_length,
                    inst.N,
                    false,
                    timeout,
                    0,
                    0,
                    :error
                ))
                println("ERROR: $e")
            end
        end
    end

    # Save results
    mkpath(output_dir)
    output_file = joinpath(output_dir, "exp6_kissat_baseline_$(timestamp).csv")

    df = DataFrame(
        instance = [r.instance for r in results],
        bit_length = [r.bit_length for r in results],
        N = [string(r.N) for r in results],
        found = [r.found for r in results],
        time = [r.time for r in results],
        decisions = [r.decisions for r in results],
        conflicts = [r.conflicts for r in results],
        status = [string(r.status) for r in results]
    )
    CSV.write(output_file, df)
    println("\nResults saved to: $output_file")

    # Print summary
    print_summary(results, bit_lengths)

    return results
end

function print_summary(results::Vector{KissatResult}, bit_lengths::Vector{Int})
    println("\n" * "="^70)
    println("Summary: Kissat Baseline")
    println("="^70)

    @printf("\n%-12s %8s %10s %12s %12s %8s\n",
        "Bit Length", "Solved", "Med Time", "Med Dec", "Med Conf", "Timeouts")
    println("-"^70)

    for bit_length in bit_lengths
        bit_results = filter(r -> r.bit_length == bit_length, results)
        isempty(bit_results) && continue

        solved = filter(r -> r.status == :solved, bit_results)
        timeouts = filter(r -> r.status == :timeout, bit_results)

        n_solved = length(solved)
        n_timeout = length(timeouts)
        n_total = length(bit_results)

        if !isempty(solved)
            med_time = median([r.time for r in solved])
            med_dec = median([r.decisions for r in solved])
            med_conf = median([r.conflicts for r in solved])
            @printf("%-12d %8s %10.3fs %12.0f %12.0f %8d\n",
                bit_length, "$(n_solved)/$(n_total)", med_time, med_dec, med_conf, n_timeout)
        else
            @printf("%-12d %8s %10s %12s %12s %8d\n",
                bit_length, "0/$(n_total)", "-", "-", "-", n_timeout)
        end
    end
    println("-"^70)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_kissat_baseline(
        bit_lengths = [32, 36, 40, 44, 48],
        max_instances = 10,
        timeout = 300.0
    )
end
