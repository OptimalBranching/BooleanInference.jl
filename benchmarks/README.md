# BooleanInference Benchmarks

This directory contains benchmarking code for BooleanInference.jl, organized as a separate Julia package with a modern **multiple dispatch architecture** to keep benchmark dependencies isolated from the main package.

## Architecture

The benchmark system uses Julia's **multiple dispatch** with abstract types to provide a clean, extensible interface for different problem types.

## Structure

```text
benchmark/
├── Project.toml              # Benchmark package dependencies
├── src/
│   ├── BooleanInferenceBenchmarks.jl  # Main benchmark module
│   ├── abstract_types.jl     # Abstract type definitions and interfaces
│   ├── generic_benchmark.jl  # Generic benchmark framework
│   ├── factoring_problem.jl  # Factoring problem implementation
│   └── utils.jl              # Generic utilities
├── scripts/
│   ├── run_benchmarks.jl     # Standalone benchmark runner
│   └── example_usage.jl      # Usage examples
├── data/                     # Generated datasets (gitignored)
└── README.md                 # This file
```

## Usage

### Quick Start

```bash
# Run example usage
julia --project=benchmark benchmark/scripts/example_usage.jl
```

### Programmatic Usage

```julia
using Pkg; Pkg.activate("benchmark")
using BooleanInferenceBenchmarks

# Create problem configurations
configs = [FactoringConfig(10, 10), FactoringConfig(12, 12)]

# Generate datasets using multiple dispatch
generate_datasets(FactoringProblem; configs=configs, per_config=100)

# Run benchmarks using multiple dispatch
results = benchmark_problem(FactoringProblem; configs=configs, samples_per_config=5)

# Run complete benchmark suite
full_results = run_full_benchmark(FactoringProblem)
```

## Adding New Problem Types

The multiple dispatch architecture makes adding new problem types extremely simple:

```julia
# 1. Define problem and config types
struct YourProblem <: AbstractBenchmarkProblem end
struct YourConfig <: AbstractProblemConfig
    param1::Int
    param2::String
end

# 2. Implement the 5 required interface methods
function generate_instance(::Type{YourProblem}, config::YourConfig; rng, include_solution=false)
    # Generate problem instance
end

function solve_instance(::Type{YourProblem}, instance)
    # Solve the instance
end

function problem_id(::Type{YourProblem}, config::YourConfig, data)
    # Generate unique ID
end

function default_configs(::Type{YourProblem})
    # Return default configurations
end

function filename_pattern(::Type{YourProblem}, config::YourConfig)
    # Generate filename pattern
end

# 3. That's it! Use the same generic functions:
generate_datasets(YourProblem)
benchmark_problem(YourProblem)
run_full_benchmark(YourProblem)
```

## Key Advantages

- **DRY Principle**: Write benchmark logic once, use for all problem types
- **Type Safety**: Julia's type system catches errors at compile time
- **Extensibility**: Adding new problems requires minimal code
- **Consistency**: All problem types use the same interface
- **Performance**: Multiple dispatch enables efficient, optimized code

## Data Management

- Datasets are generated in `benchmark/data/`
- Add `benchmark/data/` to `.gitignore` to avoid committing large files
- Use JSONL format for datasets (one JSON object per line)
