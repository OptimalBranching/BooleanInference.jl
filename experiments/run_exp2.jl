"""
Main runner for Experiment 2: BI-Direct vs BI-CnC vs march_cu-CnC

Compare:
1. BI-Direct: Direct solving with BooleanInference
2. BI-CnC: TN-based cubing + CDCL (kissat)
3. march_cu-CnC: march_cu cubing + CDCL (kissat)

Usage:
    julia run_exp2.jl [options]

Options:
    --max-instances N    Number of instances per bit size (default: 10)
    --results-dir DIR    Output directory for results (default: results)
    --bit-sizes SIZES    Comma-separated bit sizes (default: "10,12,14")
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
    end

    return parse_args(s)
end

function main()
    args = parse_commandline()

    # Parse bit sizes
    bit_sizes = [parse(Int, strip(s)) for s in split(args["bit-sizes"], ",")]

    # Locate external tools
    march_cu_path = joinpath(dirname(@__DIR__), "benchmarks", "artifacts", "bin", "march_cu")
    kissat_path = try
        String(strip(read(`which kissat`, String)))
    catch
        ""
    end

    println("\n" * "="^80)
    println("Experiment 2: BI-Direct vs BI-CnC vs march_cu-CnC")
    println("="^80)
    println("\nConfiguration:")
    println("  Max instances per bit size: $(args["max-instances"])")
    println("  Bit sizes: $(bit_sizes)")
    println("  Results directory: $(args["results-dir"])")
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
            kissat_path = kissat_path
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
    println("  - exp2_cnc_comparison_bi_direct.csv  (BI-Direct results)")
    println("  - exp2_cnc_comparison_summary.csv    (CnC results: BI-CnC & march_cu-CnC)")
    println("  - exp2_cnc_comparison_per_cube.csv   (per-cube statistics)")
    println("="^80 * "\n")

    return 0
end

# Run main if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
