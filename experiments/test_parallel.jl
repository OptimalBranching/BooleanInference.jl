"""
Quick test of parallel execution on local machine
"""

include("exp2_utils.jl")

using BooleanInference
using OptimalBranchingCore
using OptimalBranchingCore: BranchingStrategy, GreedyMerge

println("\n" * "="^80)
println("Quick Parallel Execution Test")
println("="^80)
println("Threads: $(Threads.nthreads())")

# Configuration
bsconfig = BranchingStrategy(
    table_solver = TNContractionSolver(),
    selector = MostOccurrenceSelector(3, 4),
    measure = NumUnfixedTensors(),
    set_cover_solver = GreedyMerge()
)
reducer = GammaOneReducer(40)
bi_cutoff = ProductCutoff(25000)

# Load ONE instance (16x16)
data_file = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring", "numbers_16x16.txt")
instances = load_factoring_instances(data_file; max_instances=1)

if isempty(instances)
    error("No instances loaded!")
end

inst = instances[1]
println("\nTest instance: $(inst.name)")
println("  N = $(inst.N) = $(inst.p) x $(inst.q)")

# Test with parallel=true
println("\n--- Testing with parallel=true ---")
println("BI-CnC:")
print("  Cubing... ")
flush(stdout)
result_parallel = run_bi_cnc_experiment(
    inst.n, inst.m, inst.N,
    bi_cutoff, bsconfig, reducer;
    parallel=true
)

# Test with parallel=false
println("\n--- Testing with parallel=false ---")
println("BI-CnC:")
print("  Cubing... ")
flush(stdout)
result_serial = run_bi_cnc_experiment(
    inst.n, inst.m, inst.N,
    bi_cutoff, bsconfig, reducer;
    parallel=false
)

# Compare
println("\n" * "="^80)
println("Comparison:")
println("="^80)
println("Parallel mode:")
@printf("  Cubing: %.2fs, %d cubes\n", result_parallel.cubing_time, result_parallel.n_cubes)
@printf("  Solving: wall=%.2fs, serial=%.2fs, speedup=%.2fx\n",
    result_parallel.wall_clock_solve_time,
    result_parallel.total_solve_time,
    result_parallel.total_solve_time / result_parallel.wall_clock_solve_time)

println("\nSerial mode:")
@printf("  Cubing: %.2fs, %d cubes\n", result_serial.cubing_time, result_serial.n_cubes)
@printf("  Solving: %.2fs\n", result_serial.total_solve_time)

@printf("\nParallel vs Serial solving speedup: %.2fx\n",
    result_serial.total_solve_time / result_parallel.wall_clock_solve_time)
println("="^80)
