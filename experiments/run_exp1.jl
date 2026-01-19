"""
Main runner for Experiment 1: OB Framework Design Choices

This script runs all sub-experiments:
- Exp 1.1: Branching rule comparison
- Exp 1.2: Region selector comparison
- Exp 1.3: Measure function comparison
- Exp 1.4: Region size sweep

And generates all plots.

Usage:
    julia run_exp1.jl [options]

Options:
    --max-instances N    Number of instances to test (default: 10)
    --timeout T          Timeout per instance in seconds (default: 300.0)
    --results-dir DIR    Output directory for results (default: results)
    --plots-dir DIR      Output directory for plots (default: plots)
    --experiments EXPS   Which experiments to run (default: all)
                         Format: comma-separated list, e.g., "1.1,1.2"
    --skip-plots         Don't generate plots after experiments
"""

include("exp1_1_branching_rules.jl")
include("exp1_2_region_selectors.jl")
include("exp1_3_measure_functions.jl")
include("exp1_4_region_size.jl")
include("exp1_plots.jl")

using ArgParse

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table! s begin
        "--max-instances"
            help = "Number of instances to test"
            arg_type = Int
            default = 10
        "--results-dir"
            help = "Output directory for results"
            arg_type = String
            default = "results"
        "--plots-dir"
            help = "Output directory for plots"
            arg_type = String
            default = "plots"
        "--experiments"
            help = "Which experiments to run (e.g., '1.1,1.2')"
            arg_type = String
            default = "all"
        "--skip-plots"
            help = "Don't generate plots after experiments"
            action = :store_true
    end

    return parse_args(s)
end

function main()
    args = parse_commandline()

    # Parse which experiments to run
    if args["experiments"] == "all"
        experiments_to_run = ["1.1", "1.2", "1.3", "1.4"]
    else
        experiments_to_run = split(args["experiments"], ",")
    end

    println("\n" * "="^80)
    println("Experiment 1: OB Framework Design Choices")
    println("="^80)
    println("\nConfiguration:")
    println("  Max instances: $(args["max-instances"])")
    println("  Results directory: $(args["results-dir"])")
    println("  Plots directory: $(args["plots-dir"])")
    println("  Experiments to run: $(join(experiments_to_run, ", "))")
    println("  Generate plots: $(args["skip-plots"] ? "No" : "Yes")")
    println("="^80)

    # Create output directories
    mkpath(args["results-dir"])
    if !args["skip-plots"]
        mkpath(args["plots-dir"])
    end

    # Common parameters
    common_params = Dict(
        :max_instances => args["max-instances"],
        :output_dir => args["results-dir"]
    )

    # Run each experiment
    for exp in experiments_to_run
        if exp == "1.1"
            println("\n\nRunning Experiment 1.1: Branching Rule Comparison")
            println("="^80)
            try
                run_exp1_1(; common_params...)
            catch e
                @error "Experiment 1.1 failed" exception=(e, catch_backtrace())
            end

        elseif exp == "1.2"
            println("\n\nRunning Experiment 1.2: Region Selector Comparison")
            println("="^80)
            try
                run_exp1_2(; common_params...)
            catch e
                @error "Experiment 1.2 failed" exception=(e, catch_backtrace())
            end

        elseif exp == "1.3"
            println("\n\nRunning Experiment 1.3: Measure Function Comparison")
            println("="^80)
            try
                run_exp1_3(; common_params...)
            catch e
                @error "Experiment 1.3 failed" exception=(e, catch_backtrace())
            end

        elseif exp == "1.4"
            println("\n\nRunning Experiment 1.4: Region Size Sweep")
            println("="^80)
            try
                run_exp1_4(; common_params...)
            catch e
                @error "Experiment 1.4 failed" exception=(e, catch_backtrace())
            end

        else
            @warn "Unknown experiment: $exp"
        end
    end

    # Generate plots
    if !args["skip-plots"]
        println("\n\nGenerating plots...")
        println("="^80)
        try
            generate_all_exp1_plots(args["results-dir"]; output_dir=args["plots-dir"])
        catch e
            @error "Plot generation failed" exception=(e, catch_backtrace())
        end
    end

    println("\n" * "="^80)
    println("Experiment 1 completed!")
    println("="^80)
    println("\nResults saved to: $(args["results-dir"])/")
    if !args["skip-plots"]
        println("Plots saved to: $(args["plots-dir"])/")
    end
    println("\nNext steps:")
    println("  1. Review results: ls -lh $(args["results-dir"])/")
    println("  2. View plots: open $(args["plots-dir"])/*.pdf")
    println("  3. Analyze data: julia -e 'include(\"exp1_utils.jl\"); results = load_results(\"$(args["results-dir"])/exp1_1_branching_rules\")'")
    println("="^80 * "\n")
end

# Run main if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
