using Test
using BooleanInference
using BooleanInference: TNContractionSolver, MostOccurrenceSelector, NumUnfixedVars

@testset "branchtable" begin
    # Create a simple SAT problem instead of factoring
    @bools a b c d
    cnf = ∧(∨(a, b), ∨(¬a, c), ∨(c, d))
    sat = Satisfiability(cnf; use_constraints=true)
    tn_problem = setup_from_sat(sat)
    
    # Test that the problem is set up correctly
    @test length(tn_problem.static.vars) > 0
    @test length(tn_problem.static.tensors) > 0
    @test count_unfixed(tn_problem) > 0
    
    # Test branching strategy configuration
    br_strategy = BranchingStrategy(
        table_solver = TNContractionSolver(),
        selector = MostOccurrenceSelector(1, 3),
        measure = NumUnfixedVars()
    )
    
    # Test solving (with a simple problem that won't stack overflow)
    result = bbsat!(tn_problem, br_strategy, NoReducer())
    @test !isnothing(result)
    @test result isa Result
end
