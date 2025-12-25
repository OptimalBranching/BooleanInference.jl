# BooleanInference Benchmarks

This directory contains a comprehensive benchmarking suite for BooleanInference.jl, organized as a separate Julia package with a **multiple dispatch architecture** to keep benchmark dependencies isolated from the main package.

## Features

- **Multiple Problem Types**: Support for Factoring, CircuitSAT, and CNFSAT problems
- **Multiple Solvers**: Compare BooleanInference with IP solvers (Gurobi, HiGHS), X-SAT, Kissat, and Minisat
- **Dataset Management**: Generate, load, and manage benchmark datasets
- **Result Analysis**: Comprehensive result tracking, comparison, and visualization
- **Extensible Architecture**: Easy to add new problem types and solvers via multiple dispatch

## Structure

```text
benchmarks/
├── Project.toml                    # Benchmark package dependencies
├── README.md                       # This file
├── src/
│   ├── BooleanInferenceBenchmarks.jl  # Main benchmark module
│   ├── abstract_types.jl           # Abstract type definitions and interfaces
│   ├── benchmark.jl                # Generic benchmark framework
│   ├── comparison.jl               # Solver comparison utilities
│   ├── formatting.jl               # Output formatting
│   ├── result_io.jl                # Result I/O and analysis
│   ├── utils.jl                    # Generic utilities
│   ├── solver/                     # Solver implementations
│   │   ├── solver_ip.jl            # IP solver (Gurobi, HiGHS)
│   │   ├── solver_xsat.jl          # X-SAT solver
│   │   └── solver_cnfsat.jl        # CNF SAT solvers (Kissat, Minisat)
│   ├── factoring/                  # Factoring problem
│   │   ├── types.jl                # Type definitions
│   │   ├── interface.jl            # Problem interface
│   │   ├── generators.jl           # Instance generators
│   │   ├── solvers.jl              # Problem-specific solvers
│   │   └── dataset.jl              # Dataset management
│   ├── circuitSAT/                 # Circuit SAT problem
│   │   ├── types.jl                # Type definitions
│   │   ├── interface.jl            # Problem interface
│   │   ├── dataset.jl              # Dataset management
│   │   └── solvers.jl              # Problem-specific solvers
│   ├── CNFSAT/                     # CNF SAT problem
│   │   ├── types.jl                # Type definitions
│   │   ├── parser.jl               # CNF file parser
│   │   ├── interface.jl            # Problem interface
│   │   ├── dataset.jl              # Dataset management
│   │   └── solvers.jl              # Problem-specific solvers
│   └── circuitIO/                  # Circuit I/O utilities
│       └── circuitIO.jl            # Verilog/AIGER format support
├── examples/
│   ├── factoring_example.jl        # Factoring benchmark example
│   ├── circuitsat_example.jl       # CircuitSAT benchmark example
│   ├── cnfsat_example.jl           # CNFSAT benchmark example
│   └── plot/                       # Visualization scripts
│       ├── branch_comparison_main.jl
│       ├── branch_measure_comparison_*.jl
│       ├── branch_selector_comparison.jl
│       └── scatter_branch_time.jl
├── data/                           # Generated datasets (gitignored)
├── results/                        # Benchmark results
├── artifacts/                      # Generated artifacts
└── third-party/                    # Third-party tools
    ├── abc/                        # ABC synthesis tool
    ├── aiger/                      # AIGER format tools
    ├── CnC/                        # CnC solver
    ├── x-sat/                      # X-SAT solver
    └── cir_bench/                  # Circuit benchmarks
```

## Quick Start

### Installation

```bash
cd benchmarks
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Running Examples

```bash
# Run factoring benchmark
julia --project=. examples/factoring_example.jl

# Run CircuitSAT benchmark
julia --project=. examples/circuitsat_example.jl

# Run CNFSAT benchmark
julia --project=. examples/cnfsat_example.jl
```

## Usage

### Factoring Problems

```julia
using Pkg; Pkg.activate("benchmarks")
using BooleanInferenceBenchmarks

# Create problem configurations
configs = [FactoringConfig(10, 10), FactoringConfig(12, 12)]

# Generate datasets
generate_factoring_datasets(configs; per_config=100)

# Run benchmarks
results = benchmark_dataset(FactoringProblem; configs=configs)

# Compare different solvers
comparison = run_solver_comparison(FactoringProblem; configs=configs)
print_solver_comparison_summary(comparison)
```

### CircuitSAT Problems

```julia
using BooleanInferenceBenchmarks

# Load circuit datasets from Verilog or AIGER files
configs = create_circuitsat_configs("data/circuits")
instances = load_circuit_datasets(configs)

# Run benchmark
results = benchmark_dataset(CircuitSATProblem; configs=configs)
```

### CNFSAT Problems

```julia
using BooleanInferenceBenchmarks

# Parse CNF file
cnf = parse_cnf_file("problem.cnf")

# Create config and load dataset
configs = create_cnfsat_configs("data/cnf")
instances = load_cnf_datasets(configs)

# Benchmark with different solvers
results = run_solver_comparison(CNFSATProblem; configs=configs)
```

## Available Solvers

| Solver | Description | Problem Types |
|--------|-------------|---------------|
| `BooleanInferenceSolver` | Main tensor network solver | All |
| `IPSolver` | Integer Programming (Gurobi/HiGHS) | Factoring, CircuitSAT |
| `XSATSolver` | X-SAT solver | CircuitSAT, CNFSAT |
| `KissatSolver` | Kissat SAT solver | CNFSAT |
| `MinisatSolver` | Minisat SAT solver | CNFSAT |

### List Available Solvers

```julia
# List all solvers for a problem type
list_available_solvers(FactoringProblem)
list_available_solvers(CircuitSATProblem)
list_available_solvers(CNFSATProblem)
```

## Adding New Problem Types

The multiple dispatch architecture makes adding new problem types simple:

```julia
# 1. Define problem and config types
struct YourProblem <: AbstractBenchmarkProblem end

struct YourConfig <: AbstractProblemConfig
    param1::Int
    param2::String
end

struct YourInstance <: AbstractInstance
    config::YourConfig
    data::Any
end

# 2. Implement required interface methods
function generate_instance(::Type{YourProblem}, config::YourConfig; rng=Random.GLOBAL_RNG)
    # Generate problem instance
    return YourInstance(config, data)
end

function solve_instance(::Type{YourProblem}, solver::AbstractSolver, instance::YourInstance)
    # Solve the instance
    return result
end

function verify_solution(::Type{YourProblem}, instance::YourInstance, solution)
    # Verify the solution
    return is_correct
end

function problem_id(::Type{YourProblem}, instance::YourInstance)
    # Generate unique ID
    return id_string
end

# 3. That's it! Use the same generic functions:
benchmark_dataset(YourProblem; configs=your_configs)
run_solver_comparison(YourProblem; configs=your_configs)
```

## Result Management

### Saving Results

```julia
# Results are automatically saved during benchmarking
result = benchmark_dataset(FactoringProblem; configs=configs)
save_benchmark_result(result, "results/factoring_benchmark.json")
```

### Loading and Analyzing Results

```julia
# Load results
results = load_all_results("results/")

# Filter and compare
filtered = filter_results(results; problem_type=FactoringProblem)
comparison = compare_results(filtered)
print_detailed_comparison(comparison)
```

## Visualization

The `examples/plot/` directory contains scripts for generating visualizations:

```bash
# Generate branching comparison plots
julia --project=. examples/plot/branch_comparison_main.jl

# Generate measure comparison plots
julia --project=. examples/plot/branch_measure_comparison_mostocc.jl

# Generate selector comparison plots
julia --project=. examples/plot/branch_selector_comparison.jl
```

## Third-Party Tools

The `third-party/` directory contains external tools used for benchmarking:

- **abc**: ABC synthesis and verification tool
- **aiger**: AIGER format tools for circuit representation
- **CnC**: Cube-and-Conquer solver
- **x-sat**: X-SAT solver
- **cir_bench**: Circuit benchmark suite

Build third-party tools:
```bash
cd third-party
make all
```

## Key Advantages

- **DRY Principle**: Write benchmark logic once, use for all problem types
- **Type Safety**: Julia's type system catches errors at compile time
- **Extensibility**: Adding new problems/solvers requires minimal code
- **Consistency**: All problem types use the same interface
- **Performance**: Multiple dispatch enables efficient, optimized code
- **Reproducibility**: Dataset and result management ensures reproducible experiments

## Data Management

- Datasets are stored in `benchmarks/data/`
- Results are saved in `benchmarks/results/`
- Add `benchmarks/data/` to `.gitignore` to avoid committing large files
- Use JSONL format for datasets (one JSON object per line)
- Results include solver configuration, timing, and solution verification

## Dependencies

Key dependencies include:
- [BenchmarkTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl) - Benchmarking utilities
- [JuMP.jl](https://github.com/jump-dev/JuMP.jl) - Mathematical optimization
- [Gurobi.jl](https://github.com/jump-dev/Gurobi.jl) - Gurobi optimizer interface
- [HiGHS.jl](https://github.com/jump-dev/HiGHS.jl) - HiGHS optimizer interface
- [JSON3.jl](https://github.com/quinnj/JSON3.jl) - JSON serialization
