"""
Experiment 2: BI-CnC vs march_cu-CnC Comparison

Compare two CnC solving approaches on factoring problems:
1. BI-CnC: TN-based cubing + CDCL (kissat) for each cube
2. march_cu-CnC: march_cu cubing + CDCL (kissat) for each cube

Key feature: ALL cubes are evaluated (not stopping on first SAT) to collect complete statistics.
"""

include("exp2_utils.jl")

using BooleanInference
using OptimalBranchingCore
using OptimalBranchingCore: BranchingStrategy, GreedyMerge

function run_exp2(;
    max_instances::Int = 10,
    output_dir::String = "results",
    bit_sizes::Vector{Int} = [10, 12, 14],
    data_dir::String = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring"),
    march_cu_path::String = joinpath(dirname(@__DIR__), "benchmarks", "artifacts", "bin", "march_cu"),
    kissat_path::String = String(strip(read(`which kissat`, String))),
    parallel::Bool = true
)
    println("\n" * "="^80)
    println("Experiment 2: BI-CnC vs march_cu-CnC")
    println("="^80)
    println("Bit sizes: $(bit_sizes)")
    println("Threads: $(Threads.nthreads())")
    println("Parallel execution: $(parallel && Threads.nthreads() > 1 ? "enabled" : "disabled")")

    # Create experiment metadata
    metadata = get_experiment_metadata(
        "exp2_cnc_comparison",
        description="Compare BI-CnC and march_cu-CnC solving approaches on factoring problems."
    )
    metadata["parameters"] = Dict{String,Any}(
        "max_instances" => max_instances,
        "bit_sizes" => bit_sizes,
        "march_cu_path" => march_cu_path,
        "kissat_path" => kissat_path,
        "parallel" => parallel,
        "num_threads" => Threads.nthreads()
    )

    # Load instances from all bit sizes
    instances = []
    for bs in bit_sizes
        data_file = joinpath(data_dir, "numbers_$(bs)x$(bs).txt")
        if isfile(data_file)
            bs_instances = load_factoring_instances(data_file; max_instances=max_instances)
            append!(instances, bs_instances)
            println("Loaded $(length(bs_instances)) instances from $data_file")
        else
            @warn "Data file not found: $data_file"
        end
    end
    println("Total instances: $(length(instances))")

    # Check march_cu
    has_march_cu = isfile(march_cu_path)
    if !has_march_cu
        @warn "march_cu not found at $march_cu_path - will skip march_cu-CnC"
    end

    # Shared configuration for BI solvers
    bsconfig = BranchingStrategy(
        table_solver = TNContractionSolver(),
        selector = MostOccurrenceSelector(3, 4),
        measure = NumUnfixedTensors(),
        set_cover_solver = GreedyMerge()
    )
    reducer = GammaOneReducer(40)

    # CnC-specific cutoff
    bi_cutoff = ProductCutoff(25000)

    # Warm-up with simple 6x6 factoring instance
    println("\nWarming up (compiling code)...")
    try
        warmup_N = BigInt(35)  # 5 x 7, simple case
        run_bi_cnc_experiment(6, 6, warmup_N, bi_cutoff, bsconfig, reducer; parallel=parallel)
        println("Warm-up completed")
    catch e
        @warn "Warm-up failed (not critical)" exception=e
    end

    # Run experiments
    cnc_results = CnCExperimentResult[]

    for (idx, inst) in enumerate(instances)
        println("\n[$(idx)/$(length(instances))] Instance: $(inst.name)")
        println("  N = $(inst.N) = $(inst.p) x $(inst.q)")

        # BI-CnC
        println("  - BI-CnC:")
        print("    Cubing... ")
        flush(stdout)
        try
            result = run_bi_cnc_experiment(inst.n, inst.m, inst.N, bi_cutoff, bsconfig, reducer; parallel=parallel)
            push!(cnc_results, result)
        catch e
            println("FAILED: $e")
        end

        # march_cu-CnC
        if has_march_cu
            println("  - march_cu-CnC:")
            print("    Cubing... ")
            flush(stdout)
            try
                result = run_march_cnc_experiment(
                    inst.n, inst.m, inst.N;
                    march_cu_path = march_cu_path,
                    kissat_path = kissat_path,
                    parallel = parallel
                )
                push!(cnc_results, result)
            catch e
                println("FAILED: $e")
            end
        end
    end

    # Save results
    output_path = get_output_path(output_dir, "exp2_cnc_comparison")
    save_results(cnc_results, output_path; metadata=metadata)

    # Print summary
    print_summary_table(cnc_results)

    return cnc_results
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_exp2(
        max_instances = 10,
        output_dir = "results"
    )
end
