"""
Main runner for Experiment 2: BI-CnC vs march_cu-CnC Comparison

Compare:
1. BI-CnC: TN-based cubing + CDCL (kissat) for each cube
2. march_cu-CnC: march_cu cubing + CDCL (kissat) for each cube

Usage:
    julia -t <threads> run_exp2.jl [options]

Examples:
    julia -t 24 run_exp2.jl --max-instances 10 --bit-sizes "10,12,14,16"
    julia -t 1 run_exp2.jl --no-parallel  # Disable parallel execution

Options:
    --max-instances N    Number of instances per bit size (default: 10)
    --results-dir DIR    Output directory for results (default: results)
    --bit-sizes SIZES    Comma-separated bit sizes (default: "10,12,14")
    --parallel           Enable parallel cube solving (default: true)
    --no-parallel        Disable parallel cube solving
"""

include("exp2_cnc_comparison.jl")

using ArgParse

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table! s begin
        "--max-instances"
            help = "Number of instances per bit size"
            arg_type = Int
            default = 10
        "--results-dir"
            help = "Output directory for results"
            arg_type = String
            default = "results"
        "--bit-sizes"
            help = "Comma-separated bit sizes (e.g., '10,12,14')"
            arg_type = String
            default = "10,12,14"
        "--parallel"
            help = "Enable parallel cube solving"
            action = :store_true
        "--no-parallel"
            help = "Disable parallel cube solving"
            action = :store_true
    end

    return parse_args(s)
end

function main()
    args = parse_commandline()

    # Parse bit sizes
    bit_sizes = [parse(Int, strip(s)) for s in split(args["bit-sizes"], ",")]

    # Determine parallel execution
    parallel = if args["no-parallel"]
        false
    elseif args["parallel"]
        true
    else
        true  # Default: enabled
    end

    # Locate external tools
    march_cu_path = joinpath(dirname(@__DIR__), "benchmarks", "artifacts", "bin", "march_cu")
    kissat_path = try
        String(strip(read(`which kissat`, String)))
    catch
        ""
    end

    println("\n" * "="^80)
    println("Experiment 2: BI-CnC vs march_cu-CnC Comparison")
    println("="^80)
    println("\nConfiguration:")
    println("  Max instances per bit size: $(args["max-instances"])")
    println("  Bit sizes: $(bit_sizes)")
    println("  Results directory: $(args["results-dir"])")
    println("  Threads: $(Threads.nthreads())")
    println("  Parallel execution: $(parallel && Threads.nthreads() > 1 ? "enabled" : "disabled")")
    println("  march_cu: $(isfile(march_cu_path) ? march_cu_path : "NOT FOUND")")
    println("  kissat: $(isempty(kissat_path) ? "NOT FOUND" : kissat_path)")
    println("="^80)

    if isempty(kissat_path)
        @error "Kissat not found in PATH. Please install kissat."
        return 1
    end

    # Create output directory
    mkpath(args["results-dir"])

    # Run experiment
    try
        results = run_exp2(
            max_instances = args["max-instances"],
            output_dir = args["results-dir"],
            bit_sizes = bit_sizes,
            march_cu_path = march_cu_path,
            kissat_path = kissat_path,
            parallel = parallel
        )
    catch e
        @error "Experiment failed" exception=(e, catch_backtrace())
        return 1
    end

    println("\n" * "="^80)
    println("Experiment 2 completed!")
    println("="^80)
    println("\nResults saved to: $(args["results-dir"])/")
    println("\nOutput files:")
    println("  - exp2_cnc_comparison_*_summary.csv    (Summary results)")
    println("  - exp2_cnc_comparison_*_per_cube.csv   (Per-cube statistics)")
    println("  - exp2_cnc_comparison_*.json           (Complete results with metadata)")
    println("="^80 * "\n")

    return 0
end

# Run main if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
