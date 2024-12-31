using BooleanInference
using BooleanInference.GenericTensorNetworks
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using Test
using BooleanInference.GenericTensorNetworks.ProblemReductions

@testset "cnf2bip" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
    bip, syms = cnf2bip(cnf)
    @test bip.he2v == [[1, 2, 3, 4], [1, 3, 4, 5], [5, 6], [2, 7], [1]]
    @test bip.tensors[3][1] == zero(Tropical{Float64})
    @test bip.literal_num == 7
end

@testset "cir2bip" begin
    circuit = @circuit begin
        c = x ∧ y
    end
    push!(circuit.exprs, Assignment([:c],BooleanExpr(true)))
    bip, syms = cir2bip(circuit)
    @test bip.he2v == [[1, 2, 3],[1]]
    @test bip.tensors == [vec(Tropical.([0.0 0.0; -Inf -Inf;;; 0.0 -Inf; -Inf 0.0])), vec(Tropical.([-Inf, 0.0]))]
    @test bip.literal_num == 3
end

@testset "solve_sat" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
    sat = Satisfiability(cnf)
    res,dict = solve_sat(sat)
    @test res == true
    @test satisfiable(cnf, dict) == true

    cnf = ∧(∨(a), ∨(a,¬c), ∨(d,¬b), ∨(¬c,¬d), ∨(a,e), ∨(a,e,¬c), ∨(¬a))
    sat = Satisfiability(cnf)
    res,dict = solve_sat(sat)
    @test res == false
    @test satisfiable(cnf, dict) == false
end

@testset "solve_factoring" begin
    a,b = solve_factoring(5,5,31*29)
    @test a*b == 31*29
end