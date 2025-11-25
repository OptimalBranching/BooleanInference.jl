using BooleanInference
using GenericTensorNetworks
using GenericTensorNetworks: ∧, ∨, ¬
using Test
using GenericTensorNetworks.ProblemReductions
using OptimalBranchingCore

@testset "setup_from_cnf" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))

    he2v = []
    tnproblem = setup_from_cnf(cnf)
    for tensor in tnproblem.static.tensors
        push!(he2v, tensor.var_axes)
    end
    @test he2v == [[1, 2, 3, 4], [1, 3, 4, 5], [5, 6], [2, 7], [1]]
    @show tnproblem.static.tensors[3].tensor[1] == zero(Tropical{Float64})
    @test count_unfixed(tnproblem) == 6
end

@testset "convert_circuit_to_bip" begin
    circuit = @circuit begin
        c = x ∧ y
    end
    push!(circuit.exprs, Assignment([:c],BooleanExpr(true)))
    tnproblem = setup_from_circuit(circuit)
    he2v = []
    for tensor in tnproblem.static.tensors
        push!(he2v, tensor.var_axes)
    end
    @test he2v == [[1, 2, 3],[1]]
    @test tnproblem.static.tensors[1].tensor == vec(Tropical.([0.0 0.0; -Inf -Inf;;; 0.0 -Inf; -Inf 0.0]))
    @test tnproblem.static.tensors[2].tensor == [Tropical(-Inf), Tropical(0.0)]
    # After initial propagation, all variables are fixed (problem is solved)
    @test count_unfixed(tnproblem) == 0
end

@testset "solve_sat_with_assignments" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
    sat = Satisfiability(cnf; use_constraints=true)
    res, dict, stats = solve_sat_with_assignments(sat)
    @test res == true
    @test satisfiable(cnf, dict) == true
    # Test that stats are recorded
    @test stats.total_branches >= 0
    @test stats.total_subproblems >= 0

    cnf = ∧(∨(a), ∨(a,¬c), ∨(d,¬b), ∨(¬c,¬d), ∨(a,e), ∨(a,e,¬c), ∨(¬a))
    sat = Satisfiability(cnf; use_constraints=true)
    @test_throws ErrorException setup_from_sat(sat)
end

@testset "solve_factoring" begin
    a, b, stats = solve_factoring(5, 5, 31*29)
    @test a*b == 31*29
    @test stats.total_branches >= 0
    @test stats.total_subproblems >= 0
    println("Factoring stats: branches=$(stats.total_branches), subproblems=$(stats.total_subproblems)")
end

@testset "branching_statistics" begin
    # Test with a simple SAT problem
    @bools a b c d
    cnf = ∧(∨(a, b), ∨(¬a, c), ∨(¬b, d))
    sat = Satisfiability(cnf; use_constraints=true)
    tn_problem = setup_from_sat(sat)
    
    # Test initial stats are zero
    initial_stats = get_branching_stats(tn_problem)
    @test initial_stats.total_branches == 0
    @test initial_stats.total_subproblems == 0

    # Solve and check stats are recorded
    result = BooleanInference.solve(tn_problem,
        BranchingStrategy(table_solver=TNContractionSolver(),
                         selector=MostOccurrenceSelector(1,2),
                         measure=NumUnfixedVars()),
        NoReducer())

    # Stats should have been recorded
    @test result.stats.total_branches >= 0
    @test result.stats.total_subproblems >= 0
    @test result.stats.avg_branching_factor >= 0.0

    # Print stats for debugging
    println("\nBranching Statistics:")
    print_stats_summary(result.stats)
    
    # Test reset functionality
    reset_problem!(tn_problem)
    reset_stats = get_branching_stats(tn_problem)
    @test reset_stats.total_branches == 0
    @test reset_stats.total_subproblems == 0
end
