# BooleanInference.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://nzy1997.github.io/BooleanInference.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://nzy1997.github.io/BooleanInference.jl/dev/)
[![Build Status](https://github.com/nzy1997/BooleanInference.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/nzy1997/BooleanInference.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/nzy1997/BooleanInference.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/nzy1997/BooleanInference.jl)

A high-performance Julia package for solving Boolean satisfiability problems using tensor network contraction and optimal branching strategies.

## Features

- **Tensor Network Representation**: Efficiently represents Boolean satisfiability problems as tensor networks
- **Optimal Branching**: Uses advanced branching strategies to minimize search space
- **Multiple Problem Types**: Supports CNF, circuit, and factoring problems
- **High Performance**: Optimized for speed with efficient propagation and contraction algorithms
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
satisfiable, assignments, depth = solve_sat_with_assignments(sat)

println("Satisfiable: ", satisfiable)
println("Assignments: ", assignments)
```

### Solving Factoring Problems

```julia
# Factor a semiprime number
a, b = solve_factoring(5, 5, 31*29)
println("Factors: $a × $b = $(a*b)")
```

### Circuit Problems

```julia
# Solve circuit satisfiability
circuit = @circuit begin
    c = x ∧ y
end
push!(circuit.exprs, Assignment([:c], BooleanExpr(true)))

tnproblem = setup_from_circuit(circuit)
result, depth = solve(tnproblem, BranchingStrategy(), NoReducer())
```

## Core Components

### Problem Types
- `TNProblem`: Main problem representation
- `TNStatic`: Static problem structure
- `DomainMask`: Variable domain representation

### Solvers
- `TNContractionSolver`: Tensor network contraction-based solver
- `LeastOccurrenceSelector`: Variable selection strategy
- `NumUnfixedVars`: Measurement strategy

### Key Functions
- `solve()`: Main solving function
- `setup_from_cnf()`: Setup from CNF formulas
- `setup_from_circuit()`: Setup from circuit descriptions
- `solve_factoring()`: Solve integer factoring problems

## Advanced Usage

### Custom Branching Strategy

```julia
using OptimalBranchingCore: BranchingStrategy

# Configure custom solver
bsconfig = BranchingStrategy(
    table_solver=TNContractionSolver(),
    selector=LeastOccurrenceSelector(2, 10),
    measure=NumUnfixedVars()
)

# Solve with custom configuration
result, depth = solve(problem, bsconfig, NoReducer())
```

### Benchmarking

The package includes comprehensive benchmarking tools:

```julia
using BooleanInferenceBenchmarks

# Compare different solvers
configs = [(10,10), (12,12), (14,14)]
results = run_solver_comparison(FactoringProblem, configs)
print_solver_comparison_summary(results)
```

