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
    @test tnproblem.n_unfixed == 7
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
    @test tnproblem.n_unfixed == 3
end

@testset "solve_sat_with_assignments" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
    sat = Satisfiability(cnf; use_constraints=true)
    res, dict = solve_sat_with_assignments(sat)
    @test res == true
    @test satisfiable(cnf, dict) == true

    cnf = ∧(∨(a), ∨(a,¬c), ∨(d,¬b), ∨(¬c,¬d), ∨(a,e), ∨(a,e,¬c), ∨(¬a))
    sat = Satisfiability(cnf; use_constraints=true)
    res, dict, _ = solve_sat_with_assignments(sat)
    @test res == false
    # @test satisfiable(cnf, dict) == false
    @test isempty(dict)
end

@testset "solve_factoring" begin
    a,b = solve_factoring(5,5,31*29)
    @test a*b == 31*29
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