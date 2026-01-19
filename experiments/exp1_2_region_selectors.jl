"""
Experiment 1.2: Region Selector Comparison

Compare different region selectors:
- MostOccurrence: O(1), fast heuristic, may pick suboptimal variable
- MinGamma: O(n), scans all variables for minimum γ
- Lookahead: O(n), march-style propagation probing

Fixed parameters:
- branching = GreedyMerge
- k = 3
- max_tensors = 4
- measure = NumUnfixedTensors()
"""

include("exp1_utils.jl")

using BooleanInference

function run_exp1_2(; max_instances::Int=10, output_dir::String=".")
    println("\n" * "="^80)
    println("Experiment 1.2: Region Selector Comparison")
    println("="^80)

    # Create experiment metadata
    metadata = get_experiment_metadata(
        "exp1_2_region_selectors",
        description="Compare MostOccurrence, MinGamma, and Lookahead region selectors with GreedyMerge branching."
    )

    # Hardcoded parameters
    data_file = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring", "numbers_12x12.txt")
    timeout = 300.0
    # All configs use GammaOneReducer; limit=0 means scan all variables (max cost)
    reducer = GammaOneReducer(0)
    k = 3
    max_tensors = 4

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
                selector=MinGammaSelector(k, max_tensors, 0),
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

    # Define configurations: selector × GammaOneReducer(limit)
    configs = Any[]

    # GammaOneReducer sweep (limit = number of vars scanned per reduction pass)
    # limit=0 => scan all (max cost); limit>0 => bounded scan
    gamma_limits = [0, 1, 5, 10, 20, 50]
    min_gamma_limit = [0, 20, 50, 100, 200]

    # MinGamma selectors (use NoReducer, no gamma_limits sweep needed)
    for limit in min_gamma_limit
        cfg_name = "MinGamma_L$(limit)"
        push!(configs, (
            name=cfg_name,
            bsconfig=BranchingStrategy(
                table_solver=TNContractionSolver(),
                selector=MinGammaSelector(k, max_tensors, limit),
                measure=NumUnfixedTensors(),
                set_cover_solver=GreedyMerge()
            ),
            reducer=NoReducer()
        ))
    end

    # Non-MinGamma selectors × gamma_limits
    selectors = Any[]
    push!(selectors, ("MostOccurrence", MostOccurrenceSelector(k, max_tensors)))

    # LookaheadSelector sweep (n_candidates)
    lookahead_candidates = [5, 10, 25, 50, 100]
    for n in lookahead_candidates
        push!(selectors, ("Lookahead_n$(n)", LookaheadSelector(k, max_tensors, n)))
    end

    for (sel_name, sel) in selectors, glim in gamma_limits
        # Naming convention:
        # - MostOccurrence with G1(1) = pure heuristic (no real OB reduction)
        # - MostOccurrence with G1(X≠1) = MostOccurrence+OB (hybrid)
        # - Lookahead always uses OB → Lookahead+OB
        if startswith(sel_name, "MostOccurrence")
            cfg_name = glim == 1 ? "MostOccurrence" : "MostOccurrence+OB_G$(glim)"
        elseif startswith(sel_name, "Lookahead")
            cfg_name = "Lookahead+OB_$(sel_name[11:end])_G$(glim)"  # e.g. Lookahead+OB_n5_G10
        else
            cfg_name = "$(sel_name)_G$(glim)"
        end

        push!(configs, (
            name=cfg_name,
            bsconfig=BranchingStrategy(
                table_solver=TNContractionSolver(),
                selector=sel,
                measure=NumUnfixedTensors(),
                set_cover_solver=GreedyMerge()
            ),
            reducer=GammaOneReducer(glim)
        ))
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
                terminal_nodes = Base.get(result.extra_data, "terminal_nodes", 0)
                @printf("✓ %.2fs, %d terminal_nodes, γ=%.3f\n",
                    result.solve_time,
                    terminal_nodes,
                    result.avg_gamma)
            else
                println("✗ Failed/Timeout")
            end
        end
    end

    # Save results
    output_path = get_output_path(output_dir, "exp1_2_region_selectors")
    save_results(all_results, output_path; metadata=metadata)

    # Print summary
    print_summary_table(all_results; groupby=:config)

    return all_results
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_exp1_2(
        max_instances=10,
        output_dir="results"
    )
end
