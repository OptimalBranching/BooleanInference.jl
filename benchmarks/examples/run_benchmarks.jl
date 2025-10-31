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
	configs = [(10,10)] 
	dataset_per_config = 1
	
	println("\nComparing BooleanInference vs IP Solver...")
	println("Configurations: $configs")
	println("Instances per config: $dataset_per_config")
	
	# Option 1: Automatic comparison of all available solvers
	all_results = run_solver_comparison(FactoringProblem, configs; 
	                                  dataset_per_config=dataset_per_config)
	
	print_solver_comparison_summary(all_results)
end

if abspath(PROGRAM_FILE) == @__FILE__
	main()
end
