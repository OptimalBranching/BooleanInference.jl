# BooleanInference.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://anonymous.github.io/BooleanInference.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://anonymous.github.io/BooleanInference.jl/dev/)
[![Build Status](https://github.com/anonymous/BooleanInference.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/anonymous/BooleanInference.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/anonymous/BooleanInference.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/anonymous/BooleanInference.jl)

A high-performance Julia package for solving Boolean satisfiability problems using tensor network contraction and optimal branching strategies.

## Features

- **Tensor Network Representation**: Efficiently represents Boolean satisfiability problems as tensor networks
- **Optimal Branching**: Uses advanced branching strategies to minimize search space
- **Multiple Problem Types**: Supports CNF, circuit, and factoring problems
- **Circuit Simplification**: Automatic circuit simplification using constant propagation and gate optimization
- **CDCL Integration**: Supports clause learning via CaDiCaL SAT solver integration
- **2-SAT Solver**: Built-in efficient 2-SAT solver for special cases
- **High Performance**: Optimized for speed with efficient propagation and contraction algorithms
- **Visualization**: Problem structure visualization with graph-based representations
- **Flexible Interface**: Easy-to-use API for various constraint satisfaction problems

## Installation

```julia
using Pkg
Pkg.add("BooleanInference")
```

## Quick Start

### Solving SAT Problems

```julia
using BooleanInference
using GenericTensorNetworks: ∧, ∨, ¬

# Define a CNF formula
@bools a b c d e f g
cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))

# Solve and get assignments
sat = Satisfiability(cnf; use_constraints=true)
satisfiable, assignments, stats = solve_sat_with_assignments(sat)

println("Satisfiable: ", satisfiable)
println("Assignments: ", assignments)
```

### Solving Factoring Problems

```julia
# Factor a semiprime number
a, b, stats = solve_factoring(5, 5, 31*29)
println("Factors: $a × $b = $(a*b)")
```

### Circuit SAT Problems

```julia
using ProblemReductions: Circuit, Assignment, BooleanExpr

# Solve circuit satisfiability
circuit = @circuit begin
    c = x ∧ y
end
push!(circuit.exprs, Assignment([:c], BooleanExpr(true)))

satisfiable, stats = solve_circuit_sat(circuit)
```

## Core Components

### Problem Types
- `TNProblem`: Main tensor network problem representation
- `BipartiteGraph`: Static problem structure (variables and tensors)
- `DomainMask`: Variable domain representation using bitmasks
- `ClauseTensor`: Clause representation as tensor factors

### Solvers & Strategies
- `TNContractionSolver`: Tensor network contraction-based branching table solver
- `MostOccurrenceSelector`: Variable selection based on occurrence frequency
- `NumUnfixedVars`: Measurement strategy counting unfixed variables
- `NumUnfixedTensors`: Measurement based on unfixed tensor count
- `HardSetSize`: Measurement based on hard clause set size

### Key Functions

| Function | Description |
|----------|-------------|
| `solve()` | Main solving function with configurable strategy |
| `solve_sat_problem()` | Solve SAT and return satisfiability result |
| `solve_sat_with_assignments()` | Solve SAT and return variable assignments |
| `solve_circuit_sat()` | Solve circuit satisfiability problems |
| `solve_factoring()` | Solve integer factoring problems |
| `setup_from_cnf()` | Setup problem from CNF formulas |
| `setup_from_circuit()` | Setup problem from circuit descriptions |
| `setup_from_sat()` | Setup problem from CSP representation |

## Advanced Usage

### Custom Branching Strategy

```julia
using OptimalBranchingCore: BranchingStrategy, GreedyMerge

# Configure custom solver
bsconfig = BranchingStrategy(
    table_solver=TNContractionSolver(),
    selector=MostOccurrenceSelector(3, 4),
    measure=NumUnfixedTensors(),
    set_cover_solver=GreedyMerge()
)

# Solve with custom configuration
result = solve(problem, bsconfig, NoReducer())
```

### Circuit Simplification

```julia
using ProblemReductions: CircuitSAT

# Simplify a circuit before solving
simplified_circuit, var_mapping = simplify_circuit(circuit, fixed_vars)
```

### 2-SAT Solving

```julia
# Check if problem is 2-SAT reducible and solve
if is_2sat_reducible(problem)
    result = solve_2sat(problem)
end
```

### CDCL with Clause Learning

```julia
# Solve using CaDiCaL and mine learned clauses
status, model, learned_clauses = solve_and_mine(cnf; conflict_limit=30000, max_len=5)
```

### Visualization

```julia
# Visualize the problem structure
visualize_problem(problem, "output.png")

# Get and visualize highest degree variables
high_degree_vars = get_highest_degree_variables(problem, k=10)
visualize_highest_degree_vars(problem, k=10, "high_degree.png")
```

## Project Structure

```
src/
├── BooleanInference.jl    # Main module
├── interface.jl           # High-level API functions
├── core/                  # Core data structures
│   ├── static.jl          # BipartiteGraph structure
│   ├── domain.jl          # DomainMask operations
│   ├── problem.jl         # TNProblem definition
│   └── stats.jl           # BranchingStats tracking
├── branching/             # Branching algorithms
│   ├── branch.jl          # Main branching logic (bbsat!)
│   ├── propagate.jl       # Constraint propagation
│   └── measure.jl         # Measure strategies
├── branch_table/          # Branching table generation
│   ├── contraction.jl     # Tensor contraction
│   ├── selector.jl        # Variable selection
│   └── branchtable.jl     # Table generation
├── utils/                 # Utility functions
│   ├── simplify_circuit.jl # Circuit simplification
│   ├── circuit2cnf.jl     # Circuit to CNF conversion
│   ├── twosat.jl          # 2-SAT solver
│   └── visualization.jl   # Problem visualization
└── cdcl/                  # CDCL integration
    └── CaDiCaLMiner.jl    # CaDiCaL wrapper for clause learning
```

## Dependencies

Key dependencies include:
- [GenericTensorNetworks.jl](https://github.com/QuEraComputing/GenericTensorNetworks.jl) - Tensor network operations
- [OptimalBranchingCore.jl](https://github.com/OptimalBranching/OptimalBranchingCore.jl) - Branching framework
- [ProblemReductions.jl](https://github.com/GiggleLiu/ProblemReductions.jl) - Problem reduction utilities
- [Graphs.jl](https://github.com/JuliaGraphs/Graphs.jl) - Graph data structures
- [CairoMakie.jl](https://github.com/MakieOrg/Makie.jl) - Visualization

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
