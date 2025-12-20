using BooleanInference
using Test

function satisfies_cnf(cnf::Vector{Vector{Int}}, model::Vector{Int})
    for clause in cnf
        satisfied = false
        for lit in clause
            v = abs(lit)
            if v > length(model)
                continue
            end
            val = model[v]
            if val == 0
                continue
            end
            if (lit > 0 && val == 1) || (lit < 0 && val == -1)
                satisfied = true
                break
            end
        end
        if !satisfied
            return false
        end
    end
    return true
end

@testset "CDCL C++ API" begin
    libpath = BooleanInference.libeasysat_path()
    if !isfile(libpath)
        @test_skip "libeasysat not built at $(libpath)"
    else
        cnf = [[1], [2]]
        sat, model, learnt = BooleanInference.solve_cdcl(cnf)
        @test sat == true
        @test length(model) == 2
        @test satisfies_cnf(cnf, model)
        @test all(x -> x in (-1, 0, 1), model)
        @test isa(learnt, Vector{Vector{Int}})

        cnf2 = [[1], [-2]]
        sat2, model2, learnt2 = BooleanInference.solve_cdcl(cnf2; nvars=3)
        @test sat2 == true
        @test length(model2) == 3
        @test satisfies_cnf(cnf2, model2)
        @test isa(learnt2, Vector{Vector{Int}})

        cnf3 = [[1], [-1]]
        sat3, model3, learnt3 = BooleanInference.solve_cdcl(cnf3)
        @test sat3 == false
        @test model3 == Int[]
        @test isa(learnt3, Vector{Vector{Int}})

        cnf4 = [Int[]]
        sat4, model4, learnt4 = BooleanInference.solve_cdcl(cnf4)
        @test sat4 == true
        @test model4 == Int[]
        @test isa(learnt4, Vector{Vector{Int}})

        cnf5 = [[1,2,-3], [1,-2,-3], [-1,2,3], [1,2,3], [-1,2,-3]]
        sat5, model5, learnt5 = BooleanInference.solve_cdcl(cnf5)
        @show sat5, model5, learnt5
        @test sat5 == true
        @test length(model5) == 3
        @test satisfies_cnf(cnf5, model5)
        @test isa(learnt5, Vector{Vector{Int}})
    end
end


@testset "CDCL-parse CNF file" begin
    cnf, nvars = BooleanInference.parse_cnf_file(joinpath(@__DIR__, "data", "test_3cnf.cnf"))
    @test nvars == 100
    @test length(cnf) == 400
    @test all(length(clause) > 0 for clause in cnf)
    @test all(all(abs(lit) <= nvars for lit in clause) for clause in cnf)
    @test all(all(lit != 0 for lit in clause) for clause in cnf)
    sat, model, learnt = BooleanInference.solve_cdcl(cnf)
    @test sat == true
    @test length(model) == 100
    @test satisfies_cnf(cnf, model)
    @test isa(learnt, Vector{Vector{Int}})
end

@testset "CDCL-parse Circuit-CNF file" begin
    cnf, nvars = BooleanInference.parse_cnf_file(joinpath(@__DIR__, "data", "circuit.cnf"))
    @test nvars == 357
    @test length(cnf) == 1476
    @test all(length(clause) > 0 for clause in cnf)
    @test all(all(abs(lit) <= nvars for lit in clause) for clause in cnf)
    @test all(all(lit != 0 for lit in clause) for clause in cnf)
    @time sat, model, learnt = BooleanInference.solve_cdcl(cnf)
    @show learnt
end

