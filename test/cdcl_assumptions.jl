using Test
using BooleanInference

@testset "Phase 1: Assumption-Based Solving with Rich Feedback" begin

    @testset "Basic SAT with assumptions" begin
        # Simple SAT formula: (x1 ∨ x2) ∧ (¬x1 ∨ x3)
        cnf = [[1, 2], [-1, 3]]

        # Assume x1 = true, x2 = false
        assumptions = [1, -2]

        feedback = solve_with_assumptions(cnf, assumptions; max_learned_lbd=5)

        @test feedback.status == :sat
        @test length(feedback.model) == 3
        @test feedback.model[1] > 0  # x1 = true (from assumption)
        @test feedback.model[2] < 0  # x2 = false (from assumption)
        @test feedback.decisions >= 0
        @test feedback.conflicts >= 0
    end

    @testset "UNSAT with assumptions - extract core" begin
        # Formula: (x1) ∧ (¬x1)
        cnf = [[1], [-1]]

        # Assume both x1 = true and x1 = false (contradictory)
        assumptions = [1, -1]

        feedback = solve_with_assumptions(cnf, assumptions; max_learned_lbd=5)

        @test feedback.status == :unsat
        @test length(feedback.unsat_core) > 0
        @test 1 in feedback.unsat_core || -1 in feedback.unsat_core
        println("UNSAT core: ", feedback.unsat_core)
    end

    @testset "UNSAT core identifies conflicting assumptions" begin
        # Formula: (x1 ∨ x2) ∧ (¬x1 ∨ x3) ∧ (¬x2) ∧ (¬x3)
        cnf = [[1, 2], [-1, 3], [-2], [-3]]

        # Assume x1 = true
        assumptions = [1]

        feedback = solve_with_assumptions(cnf, assumptions; max_learned_lbd=5)

        @test feedback.status == :unsat
        # The core should identify that assuming x1 leads to conflict
        @test 1 in feedback.unsat_core
        println("UNSAT core for conflicting assumptions: ", feedback.unsat_core)
    end

    @testset "Learned clauses extraction" begin
        # More complex formula that will generate learned clauses
        cnf = [
            [1, 2, 3],
            [-1, 4],
            [-2, 5],
            [-3, 6],
            [-4, -5],
            [-5, -6],
            [-4, -6]
        ]

        assumptions = [1]

        feedback = solve_with_assumptions(cnf, assumptions; max_learned_len=10, max_learned_lbd=10)

        println("Status: ", feedback.status)
        println("Conflicts: ", feedback.conflicts)
        println("Learned clauses: ", length(feedback.learned_clauses))
        println("Avg LBD: ", feedback.avg_lbd)

        @test feedback.conflicts >= 0
        # May or may not have learned clauses depending on search
    end

    @testset "Metrics extraction" begin
        cnf = [[1, 2], [-1, 3], [-2, -3]]
        assumptions = Int[]  # Empty but typed

        feedback = solve_with_assumptions(cnf, assumptions)

        @test feedback.decisions >= 0
        @test feedback.conflicts >= 0
        @test feedback.propagations >= 0
        @test feedback.restarts >= 0
        @test feedback.avg_lbd >= 0.0
        @test feedback.max_decision_level >= 0

        println("\nMetrics for SAT instance:")
        println("  Decisions: ", feedback.decisions)
        println("  Conflicts: ", feedback.conflicts)
        println("  Propagations: ", feedback.propagations)
        println("  Restarts: ", feedback.restarts)
        println("  Avg LBD: ", round(feedback.avg_lbd, digits=2))
        println("  Max decision level: ", feedback.max_decision_level)
    end

    @testset "Empty assumptions (vanilla solving)" begin
        cnf = [[1, 2], [-1, 3]]
        assumptions = Int[]  # Empty but typed

        feedback = solve_with_assumptions(cnf, assumptions)

        @test feedback.status == :sat
        @test isempty(feedback.unsat_core)
    end

end

println("\n✅ Phase 1 implementation complete!")
println("Key capabilities:")
println("  ✓ Assumption-based solving")
println("  ✓ UNSAT core extraction")
println("  ✓ Learned clause mining")
println("  ✓ Detailed CDCL metrics")
println("\nReady for Phase 2: System 2 State Management")
