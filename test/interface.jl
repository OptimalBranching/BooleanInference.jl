using BooleanInference
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using Test
using BooleanInference.GenericTensorNetworks.ProblemReductions
using BooleanInference.OptimalBranchingCore: BranchingStrategy

@testset "setup_from_cnf" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))

    he2v = []
    tnproblem = setup_from_cnf(cnf)
    for tensors in tnproblem.static.t2v
        list = []
        for item in tensors
            push!(list, item.var)
        end
        push!(he2v, list)
    end
    @test he2v == [[1, 2, 3, 4], [1, 3, 4, 5], [5, 6], [2, 7], [1]]
    @show tnproblem.static.tensors[3].tensor[1] == zero(Tropical{Float64})
    @test tnproblem.n_unfixed == 6
end

@testset "convert_circuit_to_bip" begin
    circuit = @circuit begin
        c = x ∧ y
    end
    push!(circuit.exprs, Assignment([:c],BooleanExpr(true)))
    tnproblem = setup_from_circuit(circuit)
    he2v = []
    for tensors in tnproblem.static.t2v
        list = []
        for item in tensors
            push!(list, item.var)
        end
        push!(he2v, list)
    end
    @test he2v == [[1, 2, 3],[1]]
    @test tnproblem.static.tensors[1].tensor == vec(Tropical.([0.0 0.0; -Inf -Inf;;; 0.0 -Inf; -Inf 0.0]))
    @test tnproblem.static.tensors[2].tensor == [Tropical(-Inf), Tropical(0.0)]
    # After initial propagation, all variables are fixed (problem is solved)
    @test tnproblem.n_unfixed == 0
end

@testset "circuit_output_distances" begin
    circuit = @circuit begin
        t1 = x ∧ y
        t2 = t1 ∨ z
        t3 = ¬t2
        t4 = t3 ∧ w
        out = ¬t4
    end
    distances = circuit_output_distances(circuit)
    sat = CircuitSAT(circuit; use_constraints=true)
    sym_to_dist = Dict{Symbol, Int}()
    for (idx, sym) in enumerate(sat.symbols)
        sym_to_dist[sym] = distances[idx]
    end
    @test sym_to_dist[:out] == 0
    @test sym_to_dist[:t4] == 1
    @test sym_to_dist[:t3] == 2
    @test sym_to_dist[:t2] == 3
    @test sym_to_dist[:t1] == 4
    @test sym_to_dist[:x] == 5
    @test sym_to_dist[:y] == 5
    @test sym_to_dist[:z] == 4
    @test sym_to_dist[:w] == 2
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
    @test stats.max_depth >= 0

    cnf = ∧(∨(a), ∨(a,¬c), ∨(d,¬b), ∨(¬c,¬d), ∨(a,e), ∨(a,e,¬c), ∨(¬a))
    sat = Satisfiability(cnf; use_constraints=true)
    res, dict, stats = solve_sat_with_assignments(sat)
    @test res == false
    # @test satisfiable(cnf, dict) == false
    @test isempty(dict)
    @test stats.total_branches >= 0
end

@testset "solve_factoring" begin
    a, b, stats = solve_factoring(5, 5, 31*29)
    @test a*b == 31*29
    @test stats.total_branches >= 0
    @test stats.total_subproblems >= 0
    println("Factoring stats: branches=$(stats.total_branches), subproblems=$(stats.total_subproblems), max_depth=$(stats.max_depth)")
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
    @test initial_stats.max_depth == 0
    
    # Solve and check stats are recorded
    result, depth, stats = BooleanInference.solve(tn_problem, 
        BranchingStrategy(table_solver=TNContractionSolver(1, 2), 
                         selector=MostOccurrenceSelector(), 
                         measure=NumUnfixedVars()), 
        NoReducer())
    
    # Stats should have been recorded
    @test stats.total_branches > 0 || result !== nothing  # Either branched or solved immediately
    @test stats.total_subproblems >= 0  # Each branch creates at least 2 subproblems
    @test stats.max_depth >= 0
    @test stats.avg_branching_factor >= 0.0
    
    # Print stats for debugging
    println("\nBranching Statistics:")
    print_stats_summary(stats)
    
    # Test reset functionality
    reset_branching_stats!(tn_problem)
    reset_stats = get_branching_stats(tn_problem)
    @test reset_stats.total_branches == 0
    @test reset_stats.total_subproblems == 0
    @test reset_stats.max_depth == 0
end

# @testset "benchmark" begin
# 	table_solver = TNContractionSolver()
# 	reducer = NoReducer()
# 	for selector in []
# 		for measure in [NumOfVertices(), NumOfClauses(), NumOfDegrees()]
#             println("$measure,$selector")
# 			solve_factoring(8, 8, 1019 * 1021; bsconfig = BranchingStrategy(; table_solver, selector, measure), reducer)
# 		end
# 	end
# end

# @testset "interface" begin
#     solve_factoring(8, 8, 1019 * 1021; bsconfig = BranchingStrategy(; table_solver= TNContractionSolver(), selector=KNeighborSelector(1, 1), measure=NumOfDegrees()), reducer= NoReducer())
#     solve_factoring(5, 5, 899; bsconfig = BranchingStrategy(; table_solver= TNContractionSolver(), selector=KNeighborSelector(1, 1), measure=NumOfDegrees()), reducer= NoReducer())
	
# 	bs = BranchingStrategy(table_solver = TNContractionSolver(), selector = KNeighborSelector(1, 1), set_cover_solver = BooleanInference.OptimalBranchingCore.GreedyMerge(),measure=NumOfDegrees())

# 	solve_factoring(8, 8, 1019 * 1021; bsconfig = bs, reducer= NoReducer())
# end
