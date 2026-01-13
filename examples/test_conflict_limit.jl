using BooleanInference
using ProblemReductions: Factoring, reduceto, CircuitSAT
using OptimalBranchingCore: GreedyMerge

println("=" ^ 70)
println("Testing Conflict Limit Support")
println("=" ^ 70)

# Setup small factoring problem
N = 50791626551
println("\nProblem: Factor N = $N")

fproblem = Factoring(18, 18, N)
circuit_sat = reduceto(CircuitSAT, fproblem);
circuit_problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true);
tn_problem = setup_from_sat(circuit_problem)

println("Tensor Network:")
println("  Variables: ", length(tn_problem.static.vars))
println("  Tensors: ", length(tn_problem.static.tensors))

config = BranchingStrategy(
    table_solver = TNContractionSolver(),
    selector = LookaheadSelector(3, 4),
    measure = NumUnfixedTensors(),
    set_cover_solver = GreedyMerge()
)

println("\n" * "=" ^ 70)
println("Test 1: Unlimited (conflict_limit=0)")
println("=" ^ 70)

result1 = solve_with_cdcl_guidance(
    tn_problem,
    config,
    RegionBasedCubes();
    max_iterations=5,
    max_cube_size=5,
    conflict_limit=0,  # Unlimited
    adaptive_alpha=0.15,
    verbose=true
)

println("\nTest 1 Results:")
println("  Status: ", result1.status)
println("  CDCL calls: ", result1.cdcl_calls)
println("  Total conflicts: ", result1.total_conflicts)
println("  Learned clauses: ", length(result1.learned_clauses))

println("\n" * "=" ^ 70)
println("Test 2: Limited with Incremental Learning (conflict_limit=5000)")
println("=" ^ 70)
println("\nThis test demonstrates CNF strengthening across iterations:")
println("- Each probe is limited to 5000 conflicts")
println("- High-quality learned clauses (length 2-3, LBD ≤ 3) are added to CNF")
println("- Subsequent probes work with progressively strengthened formula")
println("- This creates feedback loop: probe → learn → strengthen → probe harder problem")

# Reset problem
tn_problem2 = setup_from_sat(circuit_problem)

result2 = solve_with_cdcl_guidance(
    tn_problem2,
    config,
    RegionBasedCubes();
    max_iterations=10,
    max_cube_size=5,
    conflict_limit=5000,  # Limited probing with learning
    adaptive_alpha=0.15,
    verbose=true
)

println("\nTest 2 Results:")
println("  Status: ", result2.status)
println("  CDCL calls: ", result2.cdcl_calls)
println("  Total conflicts: ", result2.total_conflicts)
println("  Avg conflicts/call: ", round(result2.total_conflicts / result2.cdcl_calls, digits=2))
println("  Total learned clauses: ", length(result2.learned_clauses))

# Analyze quality of learned clauses
high_quality = count(2 <= length(c) <= 3 && l <= 3 for (c, l) in zip(result2.learned_clauses, result2.learned_lbds))
println("  High-quality clauses (used for strengthening): ", high_quality)

println("\n" * "=" ^ 70)
println("Comparison and Key Insights")
println("=" ^ 70)
println("\nStrategy 1 - Unlimited (conflict_limit=0):")
println("  Calls: $(result1.cdcl_calls), Conflicts: $(result1.total_conflicts)")
println("  → Single deep probe, either solves or returns UNSAT")
println("\nStrategy 2 - Limited with Inheritance (conflict_limit=5000):")
println("  Calls: $(result2.cdcl_calls), Conflicts: $(result2.total_conflicts)")
println("  High-quality clauses: $high_quality")
println("  → Multiple shallow probes, each probe inherits learned clauses")
println("  → CNF grows stronger across iterations")
println("\n" * "=" ^ 70)
println("Answer to \"Should next cubing inherit this level?\"")
println("=" ^ 70)
println("\n✓ YES - Implemented incremental inheritance strategy:")
println("\n1. After each probe, filter high-quality clauses (length 2-3, LBD ≤ 3)")
println("2. Add these clauses to CNF for next iteration")
println("3. Subsequent probes work with strengthened formula")
println("4. Creates feedback loop: harder problem → better learning")
println("\nBenefits:")
println("  • Accumulated knowledge improves over time")
println("  • Each probe contributes to solving")
println("  • Balances OB-SAT guidance with CDCL learning")
println("  • Avoids wasting expensive OB-SAT computation")
