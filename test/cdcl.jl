using BooleanInference
using Test
# using CairoMakie

function satisfies_cnf(cnf::Vector{Vector{Int}}, model::Vector{Int32})
    # model[v-1] stores the assignment for variable v as a signed literal
    # i.e., model[i] is (i+1) if true, -(i+1) if false, 0 if unknown

    nvars = length(model)

    for clause in cnf
        satisfied = false
        for lit in clause
            var_idx = abs(lit)
            if var_idx > nvars
                continue
            end

            val = model[var_idx]
            if val == 0
                continue
            end

            # Check if literal matches the assignment
            # if lit > 0 (positive), we need val > 0 (true)
            # if lit < 0 (negative), we need val < 0 (false)
            if (lit > 0 && val > 0) || (lit < 0 && val < 0)
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

# Helper overload for Int check locally
function satisfies_cnf(cnf::Vector{Vector{Int}}, model::Vector{Int})
    return satisfies_cnf(cnf, Vector{Int32}(model))
end


@testset "CDCL-CaDiCaL API" begin
    # Test 1: Simple SAT
    cnf = [[1], [2]]
    # [[1], [2]] -> x1 must be true, x2 must be true
    status, model, learnt = BooleanInference.solve_and_mine(cnf)
    @test status == :sat
    @test length(model) >= 2
    @test satisfies_cnf(cnf, model)
    @test model[1] == 1
    @test model[2] == 2
    @test isa(learnt, Vector{Vector{Int32}})

    # Test 2: Simple SAT with negatives
    cnf2 = [[1], [-2]]
    # x1=true, x2=false
    status2, model2, learnt2 = BooleanInference.solve_and_mine(cnf2; nvars=3)
    @test status2 == :sat
    @test length(model2) == 3
    @test satisfies_cnf(cnf2, model2)
    @test model2[1] == 1
    @test model2[2] == -2

    # Test 3: UNSAT
    cnf3 = [[1], [-1]]
    status3, model3, learnt3 = BooleanInference.solve_and_mine(cnf3)
    @test status3 == :unsat

    # Test 4: One empty clause -> UNSAT
    cnf4 = [Int[]]
    status4, model4, learnt4 = BooleanInference.solve_and_mine(cnf4)
    @test status4 == :unsat

    # Test 5: Empty CNF (no clauses) -> SAT
    cnf5 = Vector{Int}[]
    status5, model5, learnt5 = BooleanInference.solve_and_mine(cnf5; nvars=1)
    @test status5 == :sat

    # Test 6: More complex SAT
    # (1 v 2 v -3) ^ (1 v -2 v -3) ^ (-1 v 2 v 3) ^ (1 v 2 v 3) ^ (-1 v 2 v -3)
    cnf6 = [[1, 2, -3], [1, -2, -3], [-1, 2, 3], [1, 2, 3], [-1, 2, -3]]
    status6, model6, learnt6 = BooleanInference.solve_and_mine(cnf6)
    @test status6 == :sat
    @test satisfies_cnf(cnf6, model6)
end

@testset "CDCL-parse CNF file" begin
    cnf, nvars = BooleanInference.parse_cnf_file(joinpath(@__DIR__, "data", "test.cnf"))
    @test nvars == 219
    @test length(cnf) == 903

    status, model, learnt = BooleanInference.solve_and_mine(cnf; nvars=nvars)
    @test status == :sat
    @test length(model) == nvars
    @test satisfies_cnf(cnf, model)
    @test isa(learnt, Vector{Vector{Int32}})

    learnt_lengths = [length(clause) for clause in learnt]
    @show length(learnt)

    # # Only make plot if we have learnt clauses
    # if !isempty(learnt)
    #     fig = Figure(resolution=(800, 600))
    #     ax = Axis(fig[1, 1],
    #         xlabel="Length of learnt clauses",
    #         ylabel="Frequency",
    #         title="Histogram of length of learnt clauses")
    #     hist!(ax, learnt_lengths, bins=50, color=:steelblue, strokewidth=1, strokecolor=:black)
    #     save(joinpath(@__DIR__, "learnt_clause_length_histogram_3cnf.png"), fig)
    #     @info "Histogram of length of learnt clauses saved to: $(joinpath(@__DIR__, "learnt_clause_length_histogram_3cnf.png"))"
    # end
end

@testset "CDCL-parse Circuit-CNF file" begin
    cnf, nvars = BooleanInference.parse_cnf_file(joinpath(@__DIR__, "data", "circuit.cnf"))

    @time status, model, learnt = BooleanInference.solve_and_mine(cnf; nvars=nvars, conflict_limit=0)
    @show status
    @show length(learnt)

    if status == :sat
        @test satisfies_cnf(cnf, model)
    end

    # if !isempty(learnt)
    #     learnt_lengths = [length(clause) for clause in learnt]
    #     fig = Figure(resolution=(800, 600))
    #     ax = Axis(fig[1, 1],
    #         xlabel="Length of learnt clauses",
    #         ylabel="Frequency",
    #         title="Histogram of length of learnt clauses")
    #     hist!(ax, learnt_lengths, bins=50, color=:steelblue, strokewidth=1, strokecolor=:black)
    #     save(joinpath(@__DIR__, "learnt_clause_length_histogram.png"), fig)
    #     @info "Histogram of length of learnt clauses saved to: $(joinpath(@__DIR__, "learnt_clause_length_histogram.png"))"
    # end
end

@testset "CDCL-CaDiCaLMiner limit" begin
    cnf, nvars = BooleanInference.parse_cnf_file(joinpath(@__DIR__, "data", "test.cnf"))

    # Test conflict limit
    status, model, learned = BooleanInference.solve_and_mine(cnf; conflict_limit=10, max_len=3)
    @show status
    @show length(learned)
end
