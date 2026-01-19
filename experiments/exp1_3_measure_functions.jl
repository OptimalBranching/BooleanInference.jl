"""
Experiment 1.3: Measure Function Comparison

Compare different measure functions with MinGammaSelector:
- NumUnfixedVars: Counts unfixed variables
- NumUnfixedTensors: Counts active constraints

Test configurations:
- MinGammaSelector(3,4): 14x14 only (too slow for larger)

Additionally, use Knuth tree size estimator to evaluate measure quality:
- Uniform sampling provides baseline variance
- Importance sampling tests if measure predicts subtree size well
- Lower importance sampling variance = better measure
"""

include("exp1_utils.jl")

using BooleanInference
using Printf
using ProblemReductions: CircuitSAT, Factoring, reduceto

function run_exp1_3(;
    max_instances::Int=10,
    output_dir::String="results",
    knuth_samples::Int=50  # Number of Knuth estimation samples
)
    println("\n" * "="^80)
    println("Experiment 1.3: Measure Function Comparison")
    println("="^80)

    # Create experiment metadata
    metadata = get_experiment_metadata(
        "exp1_3_measure_functions",
        description="Compare NumUnfixedVars vs NumUnfixedTensors measures with MinGammaSelector on 14x14 factoring instances. Includes Knuth estimator analysis for measure quality evaluation."
    )
    metadata["parameters"] = Dict{String,Any}(
        "max_instances" => max_instances,
        "knuth_samples" => knuth_samples,
        "selector" => "MinGammaSelector(3, 4, 0)",
        "measures" => ["NumUnfixedVars", "NumUnfixedTensors"],
        "reducer" => "NoReducer"
    )

    data_dir = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring")
    timeout = 300.0
    reducer = NoReducer()

    # =========================================================================
    # MinGammaSelector on 14x14 only
    # =========================================================================
    println("\n" * "-"^80)
    println("MinGammaSelector (14x14 only)")
    println("-"^80)

    mingamma_configs = [
        (
            name="MinGamma+NumUnfixedVars",
            bsconfig=BranchingStrategy(
                table_solver=TNContractionSolver(),
                selector=MinGammaSelector(3, 4, 0),
                measure=NumUnfixedVars(),
                set_cover_solver=GreedyMerge()
            ),
            reducer=reducer
        ),
        (
            name="MinGamma+NumUnfixedTensors",
            bsconfig=BranchingStrategy(
                table_solver=TNContractionSolver(),
                selector=MinGammaSelector(3, 4, 0),
                measure=NumUnfixedTensors(),
                set_cover_solver=GreedyMerge()
            ),
            reducer=reducer
        ),
    ]

    mingamma_results = ExperimentResult[]
    knuth_analysis_results = Dict{String, Any}()
    data_file_14 = joinpath(data_dir, "numbers_14x14.txt")

    if isfile(data_file_14)
        instances_14 = load_factoring_instances(data_file_14; max_instances=max_instances)
        println("\n[14 x 14] Loaded $(length(instances_14)) instances")

        # Warm-up
        if !isempty(instances_14)
            println("Warming up...")
            warmup_inst = instances_14[1]
            for config in mingamma_configs
                try
                    solve_factoring(warmup_inst.n, warmup_inst.m, warmup_inst.N;
                        bsconfig=config.bsconfig, reducer=config.reducer,
                        show_stats=false, cdcl_cutoff=1.0)
                catch e
                    @warn "Warm-up failed" config=config.name exception=e
                end
            end
            println("Warm-up completed")
        end

        # Run solving experiments
        for (idx, inst) in enumerate(instances_14)
            println("\n  [$(idx)/$(length(instances_14))] N=$(inst.N)")

            for config in mingamma_configs
                print("    - $(config.name)... ")
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
                    push!(mingamma_results, result)
                    @printf("✓ %.2fs, %d branches, %d conflicts\n",
                        result.solve_time,
                        result.children_explored,
                        result.unsat_leaves)
                else
                    println("✗ Failed/Timeout")
                end
            end
        end

        # =====================================================================
        # Knuth Estimator Analysis
        # =====================================================================
        println("\n" * "-"^80)
        println("Knuth Estimator Analysis (Measure Quality Evaluation)")
        println("-"^80)
        println("Using first instance for Knuth analysis with $knuth_samples samples")

        if !isempty(instances_14)
            first_inst = instances_14[1]
            println("\nAnalyzing instance: N=$(first_inst.N)")

            # Build the problem for Knuth analysis
            problem = build_factoring_problem(first_inst.n, first_inst.m, first_inst.N)

            # Run Knuth comparison for both measures
            measures = [NumUnfixedVars(), NumUnfixedTensors()]
            selector = MinGammaSelector(3, 4, 0)

            println("\nRunning Knuth tree size estimation...")
            try
                knuth_results = compare_measures_knuth(
                    problem;
                    measures=measures,
                    selector=selector,
                    num_samples=knuth_samples,
                    verbose=true
                )

                knuth_analysis_results["mingamma_14x14"] = knuth_results

                # Store summary for later
                println("\n" * "-"^50)
                println("Knuth Analysis Summary:")
                for (name, res) in knuth_results
                    uniform_var = res.uniform.log_variance
                    importance_var = res.importance.log_variance
                    ratio = importance_var / max(uniform_var, 1e-10)
                    println("  $name:")
                    println("    Uniform variance: $(round(uniform_var, digits=4))")
                    println("    Importance variance: $(round(importance_var, digits=4))")
                    println("    Variance ratio: $(round(ratio, digits=4)) (lower = better)")
                end
            catch e
                @warn "Knuth analysis failed" exception=e
            end
        end
    else
        @warn "Data file not found: $data_file_14"
    end

    # =========================================================================
    # Save results (with timestamp to avoid overwriting)
    # =========================================================================
    output_path = get_output_path(output_dir, "exp1_3_measure_functions")
    save_results(mingamma_results, output_path; metadata=metadata)

    # Save Knuth analysis results separately
    if !isempty(knuth_analysis_results)
        save_knuth_results(knuth_analysis_results, output_path; metadata=metadata)
    end

    # =========================================================================
    # Print summary
    # =========================================================================
    println("\n" * "="^80)
    println("Summary: MinGammaSelector (14x14)")
    println("="^80)
    print_summary_by_config_and_size(mingamma_results)

    return (mingamma=mingamma_results, knuth=knuth_analysis_results)
end

function print_summary_by_config_and_size(results::Vector{ExperimentResult})
    isempty(results) && return

    # Group by (config_name, bit_size)
    grouped = Dict{Tuple{String, Int}, Vector{ExperimentResult}}()
    for r in results
        key = (r.config_name, r.n)
        if !haskey(grouped, key)
            grouped[key] = ExperimentResult[]
        end
        push!(grouped[key], r)
    end

    # Get unique configs and sizes
    configs = unique(r.config_name for r in results)
    sizes = sort(unique(r.n for r in results))

    # Print header
    println()
    print(@sprintf("%-30s", "Config"))
    for s in sizes
        print(@sprintf(" | %12s", "$(s*2)-bit"))
    end
    println()
    println("-"^(30 + 15 * length(sizes)))

    # Print each metric
    for metric in [:time, :branches, :conflicts]
        for config in configs
            if metric == :time
                print(@sprintf("%-30s", config))
            elseif metric == :branches
                print(@sprintf("%-30s", "  branches"))
            else
                print(@sprintf("%-30s", "  conflicts"))
            end

            for s in sizes
                key = (config, s)
                if haskey(grouped, key)
                    data = grouped[key]
                    if metric == :time
                        med = median([r.solve_time for r in data])
                        print(@sprintf(" | %10.2fs", med))
                    elseif metric == :branches
                        med = median([r.children_explored for r in data])
                        print(@sprintf(" | %11.0f", med))
                    else
                        med = median([r.unsat_leaves for r in data])
                        print(@sprintf(" | %11.0f", med))
                    end
                else
                    print(@sprintf(" | %12s", "-"))
                end
            end
            println()
        end
        println()
    end
end

# Helper function to build factoring problem for Knuth analysis
function build_factoring_problem(n::Int, m::Int, N::Integer)
    # Create factoring problem and convert to CircuitSAT
    reduction = reduceto(CircuitSAT, Factoring(n, m, Int(N)))
    circuit_sat = CircuitSAT(reduction.circuit.circuit; use_constraints=true)

    # Convert to TN problem
    return BooleanInference.setup_from_sat(circuit_sat)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = run_exp1_3(
        max_instances=10,
        output_dir="results",
        knuth_samples=50
    )
end
