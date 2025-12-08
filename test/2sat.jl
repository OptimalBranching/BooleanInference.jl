using ProblemReductions
using ProblemReductions: BoolVar, CNFClause
using OptimalBranchingCore: GreedyMerge
using Test

@testset "2-SAT Solver Tests" begin
    # Test 1: Simple SAT 2-SAT problem
    # (x1 ∨ x2) ∧ (¬x1 ∨ x3) ∧ (¬x2 ∨ ¬x3)
    @testset "Simple SAT 2-SAT problem" begin
        cnf = CNF([
            CNFClause([BoolVar(:x1, false), BoolVar(:x2, false)]),      # x1 ∨ x2
            CNFClause([BoolVar(:x1, true), BoolVar(:x3, false)]),       # ¬x1 ∨ x3
            CNFClause([BoolVar(:x2, true), BoolVar(:x3, true)])         # ¬x2 ∨ ¬x3
        ])

        problem = setup_from_cnf(cnf)

        # Check that it's correctly identified as 2-SAT
        @test is_2sat_reducible(problem) == true

        # Solve using 2-SAT solver directly
        solution = solve_2sat(problem)

        # Should be SAT
        @test !isnothing(solution)
        @test length(solution) == length(problem.static.vars)

        # Verify solution satisfies all constraints
        @test get_var_value(solution, 1) == 1  # x1 = true
        @test get_var_value(solution, 2) == 0  # x2 = false
        @test get_var_value(solution, 3) == 1  # x3 = true
    end

    # Test 2: UNSAT 2-SAT problem
    # (x1 ∨ x2) ∧ (¬x1 ∨ x2) ∧ (x1 ∨ ¬x2) ∧ (¬x1 ∨ ¬x2)
    @testset "UNSAT 2-SAT problem" begin
        cnf = CNF([
            CNFClause([BoolVar(:x1, false), BoolVar(:x2, false)]),      # x1 ∨ x2
            CNFClause([BoolVar(:x1, true), BoolVar(:x2, false)]),       # ¬x1 ∨ x2
            CNFClause([BoolVar(:x1, false), BoolVar(:x2, true)]),       # x1 ∨ ¬x2
            CNFClause([BoolVar(:x1, true), BoolVar(:x2, true)])         # ¬x1 ∨ ¬x2
        ])

        problem = setup_from_cnf(cnf)

        @test is_2sat_reducible(problem) == true

        # Solve using 2-SAT solver
        solution = solve_2sat(problem)

        # Should be UNSAT
        @test isnothing(solution)
    end

    # Test 3: Integration with MostOccurrenceSelector
    @testset "MostOccurrenceSelector with 2-SAT detection" begin
        cnf = CNF([
            CNFClause([BoolVar(:x1, false), BoolVar(:x2, false)]),
            CNFClause([BoolVar(:x1, true), BoolVar(:x3, false)]),
            CNFClause([BoolVar(:x2, true), BoolVar(:x3, true)])
        ])

        problem = setup_from_cnf(cnf)

        bsconfig = BranchingStrategy(
            table_solver=TNContractionSolver(),
            selector=MostOccurrenceSelector(1, 2),
            measure=NumUnfixedVars(),
            set_cover_solver=GreedyMerge()
        )

        result = solve(problem, bsconfig, NoReducer(); show_stats=false)

        # Should find a solution
        @test result.found == true
        @test length(result.solution) == length(problem.static.vars)
    end
end
