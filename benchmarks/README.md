# BooleanInference Benchmarks

Benchmarking suite for BooleanInference.jl.

## Quick Start

```julia
using Pkg
Pkg.activate("benchmarks")
using BooleanInferenceBenchmarks

# Solve a circuit
result = solve("data/iscas85/c17.v")
println(result.status)  # SAT or UNSAT

# Benchmark a directory
res = benchmark("data/iscas85")
println("Median: $(median(res.times))s")
```

## API

### Core Functions

```julia
load("file.v")                    # Load instance
solve("file.v")                   # Load + solve
solve(instance, solver=...)       # Solve with custom solver
factor(N; m, n)                   # Factor integer
benchmark("dir/")                 # Benchmark directory
```

### Solver Configuration

```julia
using BooleanInference: MostOccurrenceSelector, NumUnfixedVars, NumHardTensors

# Default solver
solver = Solvers.BI()

# Custom configuration
solver = Solvers.BI(
    selector = MostOccurrenceSelector(4, 8),
    measure = NumUnfixedVars(),
    show_stats = true,
    use_cdcl = true,
    conflict_limit = 40000,
    max_clause_len = 5
)

# External solvers
solver = Solvers.Kissat(timeout=300.0)
solver = Solvers.Minisat()
solver = Solvers.Gurobi()
```

### Result

```julia
result.status    # SAT, UNSAT, TIMEOUT, UNKNOWN, ERROR
result.time      # Solve time (seconds)
result.branches  # Branch/decision count
result.solution  # Problem-specific solution
result.solver    # Solver name
```

## File Structure

```
benchmarks/src/
├── BooleanInferenceBenchmarks.jl   # Main module
├── types.jl                        # Types + Solvers module
├── problems.jl                     # Problem loading
├── solvers.jl                      # solve_instance implementations
├── api.jl                          # High-level API
└── circuitIO/                      # Circuit I/O
```

## Installation

```bash
cd benchmarks
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/quickstart.jl
```
