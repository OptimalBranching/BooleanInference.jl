"""
Experiment 1.4: Region Size Parameter Sweep

Test different region sizes:
- k ∈ {3} (fixed for now, can expand)
- max_tensors ∈ {2, 4, 6, 8}

Fixed parameters:
- selector = MinGammaSelector
- branching = GreedyMerge
- measure = NumUnfixedTensors()

Expected: Larger regions → smaller γ but exponentially higher overhead
"""

include("exp1_utils.jl")

using BooleanInference

function run_exp1_4(; max_instances::Int=10, output_dir::String=".")
    println("\n" * "="^80)
    println("Experiment 1.4: Region Size Parameter Sweep")
    println("="^80)

    # Create experiment metadata
    metadata = get_experiment_metadata(
        "exp1_4_region_size",
        description="Test different region sizes (k, max_tensors) with MinGammaSelector and GreedyMerge."
    )

    # Hardcoded parameters
    data_file = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring", "numbers_14x14.txt")
    timeout = 300.0
    reducer = NoReducer()
    k_values = [3]
    max_tensors_values = [2, 4, 6, 8]

    # Load instances
    instances = load_factoring_instances(data_file; max_instances=max_instances)
    println("\nLoaded $(length(instances)) instances from $data_file")

    # Warm-up: compile all code paths before timing
    println("\nWarming up (compiling code)...")
    warmup_inst = instances[1]
    try
        solve_factoring(warmup_inst.n, warmup_inst.m, warmup_inst.N;
            bsconfig=BranchingStrategy(
                table_solver=TNContractionSolver(),
                selector=MinGammaSelector(k_values[1], max_tensors_values[1], 0),
                measure=NumUnfixedTensors(),
                set_cover_solver=GreedyMerge()
            ),
            reducer=reducer,
            show_stats=false,
            cdcl_cutoff=1.0
        )
        println("✓ Warm-up completed")
    catch e
        @warn "Warm-up failed (not critical)" exception=e
    end

    # Generate configurations for all combinations
    configs = []
    for k in k_values
        for max_tensors in max_tensors_values
            config_name = "k$(k)_mt$(max_tensors)"
            push!(configs, (
                name=config_name,
                k=k,
                max_tensors=max_tensors,
                bsconfig=BranchingStrategy(
                    table_solver=TNContractionSolver(),
                    selector=MinGammaSelector(k, max_tensors, 0),
                    measure=NumUnfixedTensors(),
                    set_cover_solver=GreedyMerge()
                ),
                reducer=reducer
            ))
        end
    end

    println("\nTesting $(length(configs)) configurations:")
    for config in configs
        println("  - $(config.name): k=$(config.k), max_tensors=$(config.max_tensors)")
    end

    # Run experiments
    all_results = ExperimentResult[]

    for (idx, inst) in enumerate(instances)
        println("\n[$(idx)/$(length(instances))] Running instance: $(inst.name)")
        println("  N = $(inst.N) = $(inst.p) × $(inst.q)")

        for config in configs
            print("  - $(config.name)... ")
            flush(stdout)

            result = run_single_experiment(
                inst.n, inst.m, inst.N,
                config.name,
                config.bsconfig,
                config.reducer;
                timeout=timeout,
                show_stats=false
            )

            if result !== nothing
                push!(all_results, result)
                avg_configs = Base.get(result.extra_data, "avg_table_configs", 0.0)
                max_configs = Base.get(result.extra_data, "max_table_configs", 0)
                avg_vars = Base.get(result.extra_data, "avg_table_vars", 0.0)
                leaves = Base.get(result.extra_data, "terminal_nodes", 0)
                @printf("✓ %.2fs, %d leaves, γ=%.3f, table: %.1f configs (max %d), %.1f vars\n",
                    result.solve_time,
                    leaves,
                    result.avg_gamma,
                    avg_configs, max_configs, avg_vars)
            else
                println("✗ Failed/Timeout")
            end
        end
    end

    # Save results
    output_path = get_output_path(output_dir, "exp1_4_region_size")
    save_results(all_results, output_path; metadata=metadata)

    # Print summary
    print_summary_table(all_results; groupby=:config)

    return all_results
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_exp1_4(
        max_instances=10,
        output_dir="results"
    )
end
