#!/usr/bin/env julia

"""
Multiplier Verification Miter Benchmark Example

This example demonstrates solving multiplier verification miter circuits
using BooleanInference (OB-SAT) directly from Circuit representation.

Miter circuits compare two multiplier implementations:
- SAT = implementations differ (bug found)
- UNSAT = implementations equivalent
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using BooleanInference
using ProblemReductions

# Include the miter generation code
include(joinpath(@__DIR__, "..", "scripts", "generate_multver_miter.jl"))

# ============================================================================
# Solve Circuit with BI
# ============================================================================

function solve_miter_with_bi(n::Int, m::Int; buggy::Bool=false, bug_type::Symbol=:stuck_zero, show_stats::Bool=true)
    """Build and solve a multiplier miter circuit with BooleanInference."""

    bug_pos = (n÷2, m÷2)
    bug_str = buggy ? "$(bug_type)_$(bug_pos[1])_$(bug_pos[2])" : "equiv"

    println("Building $(n)×$(m) miter ($bug_str)...")

    # Build circuit
    circuit, A, B, miter_out = build_multiplier_miter(n, m; buggy=buggy, bug_type=bug_type, bug_pos=bug_pos)

    # Add constraint: miter_out must be TRUE
    push!(circuit.exprs, Assignment([miter_out], BooleanExpr(true)))

    ngates = length(circuit.exprs)
    println("  Gates: $ngates")

    # Create CircuitSAT problem
    circuit_sat = CircuitSAT(circuit)

    # Solve with BI
    bsconfig = BooleanInference.BranchingStrategy(
        table_solver=BooleanInference.TNContractionSolver(),
        selector=BooleanInference.MostOccurrenceSelector(3, 4),
        set_cover_solver=BooleanInference.GreedyMerge(),
        measure=BooleanInference.NumUnfixedTensors()
    )
    solver = BooleanInferenceSolver(bsconfig, BooleanInference.NoReducer(), show_stats, 1.0)

    result = solve_instance(CircuitSATProblem,
        CircuitSATInstance("miter_$(n)x$(m)_$(bug_str)", circuit, :generated, ""),
        solver)

    println("\nBI Result: $(result.status)")
    println("  Time: $(round(result.time, digits=3))s")
    println("  γ>1 branches: $(result.branches)")
    println("  γ=1 reductions: $(result.gamma_one)")
    if result.gamma_one_vars > 0 || result.branch_vars > 0
        println("  Vars by γ=1: $(result.gamma_one_vars)")
        println("  Vars by branches: $(result.branch_vars)")
    end

    return result
end

# ============================================================================
# Compare with march -p
# ============================================================================

function solve_miter_with_march(n::Int, m::Int; buggy::Bool=false, bug_type::Symbol=:stuck_zero)
    """Solve with march_cu -p for comparison."""
    march_cu = joinpath(dirname(@__DIR__), "artifacts", "bin", "march_cu")

    if !isfile(march_cu)
        @warn "march_cu not found"
        return nothing
    end

    bug_pos = (n÷2, m÷2)
    bug_str = buggy ? "$(bug_type)_$(bug_pos[1])_$(bug_pos[2])" : "equiv"
    cnf_path = joinpath(dirname(@__DIR__), "data", "multver", "miter_$(n)x$(m)_$(bug_str).cnf")

    if !isfile(cnf_path)
        @warn "CNF file not found: $cnf_path"
        return nothing
    end

    println("\nRunning march -p...")
    # march returns exit code 10 for SAT, 20 for UNSAT - use ignorestatus
    output = read(ignorestatus(`$march_cu $cnf_path -p`), String)

    # Parse results
    status = occursin("SATISFIABLE", output) && !occursin("UNSATISFIABLE", output) ? :sat :
             occursin("UNSATISFIABLE", output) ? :unsat : :unknown

    time_match = match(r"time = ([\d.]+)", output)
    nodes_match = match(r"nodeCount: (\d+)", output)
    dead_ends_match = match(r"dead ends in main: (\d+)", output)

    time = !isnothing(time_match) ? parse(Float64, time_match.captures[1]) : NaN
    nodes = !isnothing(nodes_match) ? parse(Int, nodes_match.captures[1]) : -1
    dead_ends = !isnothing(dead_ends_match) ? parse(Int, dead_ends_match.captures[1]) : -1

    println("march result: $status")
    println("  Time: $(time)s")
    println("  Nodes: $nodes")
    println("  Dead ends: $dead_ends")

    return (status=status, time=time, nodes=nodes, dead_ends=dead_ends)
end

# ============================================================================
# Main
# ============================================================================

function main()
    println("=" ^ 70)
    println("Multiplier Verification Miter Benchmark")
    println("=" ^ 70)
    println()

    # Test cases: (n, m, buggy, bug_type, expected)
    test_cases = [
        (4, 4, true, :stuck_zero, :sat),
        (4, 4, false, :stuck_zero, :unsat),
        (6, 6, true, :stuck_zero, :sat),
        (6, 6, false, :stuck_zero, :unsat),
        (8, 8, true, :stuck_zero, :sat),
        (8, 8, false, :stuck_zero, :unsat),
    ]

    results = []

    for (n, m, buggy, bug_type, expected) in test_cases
        bug_str = buggy ? "$(bug_type)" : "equiv"

        println("-" ^ 70)
        println("Testing: $(n)×$(m) miter ($bug_str), expected: $expected")
        println("-" ^ 70)

        # Solve with BI
        bi_result = solve_miter_with_bi(n, m; buggy=buggy, bug_type=bug_type, show_stats=false)

        # Solve with march
        march_result = solve_miter_with_march(n, m; buggy=buggy, bug_type=bug_type)

        # Verify
        bi_status = bi_result.status == SAT ? :sat : :unsat
        if bi_status != expected
            @error "BI returned wrong result! Expected $expected, got $bi_status"
        end

        push!(results, (
            name = "$(n)×$(m)_$(bug_str)",
            expected = expected,
            bi_time = bi_result.time,
            bi_branches = bi_result.branches,
            bi_gamma_one = bi_result.gamma_one,
            march_time = !isnothing(march_result) ? march_result.time : NaN,
            march_dead_ends = !isnothing(march_result) ? march_result.dead_ends : -1
        ))

        println()
    end

    # Summary
    println("=" ^ 70)
    println("Summary")
    println("=" ^ 70)
    println()
    println("| Instance | Expected | BI time | BI γ>1 | BI γ=1 | march time | march dead |")
    println("|----------|----------|---------|--------|--------|------------|------------|")

    for r in results
        println("| $(r.name) | $(r.expected) | $(round(r.bi_time, digits=2))s | $(r.bi_branches) | $(r.bi_gamma_one) | $(round(r.march_time, digits=2))s | $(r.march_dead_ends) |")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
