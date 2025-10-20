# Comprehensive solver comparison benchmark script
# Demonstrates both automatic and manual solver comparison approaches
# Usage: julia --project=benchmark benchmark/examples/run_benchmarks.jl

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks

using Gurobi
const GUROBI_ENV = Gurobi.Env()

function main()
	println("Running BooleanInference Solver Comparison Benchmarks...")
	
	# Show available solvers
	println("\nAvailable solvers:")
	list_available_solvers(FactoringProblem)
	
	# Configure benchmark parameters
	configs = [(10,10), (12,12), (14,14)] 
	dataset_per_config = 10
	
	println("\nComparing BooleanInference vs IP Solver...")
	println("Configurations: $configs")
	println("Instances per config: $dataset_per_config")
	
	# Option 1: Automatic comparison of all available solvers
	# println("\n=== Automatic Solver Comparison (All Available Solvers) ===")
	all_results = run_solver_comparison(FactoringProblem, configs; 
	                                  dataset_per_config=dataset_per_config)
	
	# Print beautiful comparison table
	print_solver_comparison_summary(all_results)
	# Persist comparison results
	save_solver_comparison(FactoringProblem, all_results; note="demo run")
	
	# # Option 2: Manual head-to-head comparison for detailed analysis
	# println("\n=== Head-to-Head Comparison (Detailed Analysis) ===")
	
	# # Test BooleanInference solver
	# println("Benchmarking BooleanInference solver...")
	# bi_results = run_full_benchmark(FactoringProblem, configs;
	#                                dataset_per_config=dataset_per_config, 
	#                                solver=BooleanInferenceSolver())
	
	# # Test IP solver
	# println("Benchmarking IP solver...")
	# ip_results = run_full_benchmark(FactoringProblem, configs;
	#                                dataset_per_config=dataset_per_config,
	#                                solver=IPSolver(Gurobi.Optimizer, GUROBI_ENV))
	
	# # Side-by-side comparison
	# println("\nHead-to-Head Results:")
	# compare_solver_results("BooleanInference", bi_results, "IP-Gurobi", ip_results)

	# println("\nAll benchmarks completed!")
	# println("Datasets cached in: benchmarks/data/factoring/")
	# println("Results saved in: benchmarks/data/factoring_benchmark_results.json")
	
	# println("\nFor quick one-liner comparisons, you can also use:")
	# println("   # Compare all solvers automatically:")
	# println("   run_solver_comparison(FactoringProblem, [(10,10)])")
	# println("   # Or test a specific solver:")
	# println("   run_full_benchmark(FactoringProblem, [(10,10)]; solver=BooleanInferenceSolver())")
end

if abspath(PROGRAM_FILE) == @__FILE__
	main()
end
