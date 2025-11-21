using Test
using BooleanInference

@testset "branchtable" begin
    tn_problem = factoring_problem(12,12,10371761)
    region = BooleanInference.select_region(tn_problem, NumUnfixedVars(), MostOccurrenceSelector(1,2))
    @test region.boundary_vars == [9, 10, 87, 93]
    @test region.inner_vars == []
    @test length(tn_problem.propagated_cache) == 0

    table, variables = BooleanInference.branching_table!(tn_problem, TNContractionSolver(), region)
    @test length(table.table) == 2
    @test variables == [9, 10, 87, 93]
    @test table.table[2] == [UInt64(15)]
    @test length(tn_problem.propagated_cache) == 2
end