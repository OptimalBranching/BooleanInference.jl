using Test
using BooleanInference

@testset "branchtable" begin
    tn_problem = factoring_problem(12,12,10371761)
    region = BooleanInference.select_region(tn_problem, NumUnfixedVars(), MostOccurrenceSelector(1,3))
    @show region

    table, variables = BooleanInference.branching_table!(tn_problem, TNContractionSolver(), region)
    @show table
end