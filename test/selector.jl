using Test
using BooleanInference
using BooleanInference: TNProblem, MostOccurrenceSelector, MinGammaSelector, TNContractionSolver, NumUnfixedVars, setup_problem
using OptimalBranchingCore
using TropicalNumbers

const dummy_tensors_to_vars = [[1, 2], [2, 3], [2]]
const dummy_tensor_data = [
    fill(Tropical(0.0), 4),
    fill(Tropical(0.0), 4),
    fill(Tropical(0.0), 2)
]

function build_dummy_problem()
    static = BooleanInference.setup_problem(3, dummy_tensors_to_vars, dummy_tensor_data)
    return TNProblem(static)
end

@testset "MostOccurrenceSelector" begin
    problem = build_dummy_problem()
    selector = MostOccurrenceSelector()
    chosen = OptimalBranchingCore.select_variables(problem, NumUnfixedVars(), selector)
    
    # Variable 2 appears in all 3 tensors, so it should be selected
    # Variable 1 appears in tensor 1, variable 3 appears in tensor 2
    @test chosen == 2
end

# Mock implementations for MinGammaSelector testing
struct MockTableSolver <: OptimalBranchingCore.AbstractTableSolver end
struct MockSetCoverSolver <: OptimalBranchingCore.AbstractSetCoverSolver end

# Gamma values for testing: var 2 has lower gamma, var 3 has higher gamma
const gamma_values = Dict(2 => 0.25, 3 => 0.9)

function OptimalBranchingCore.branching_table(
    ::TNProblem, 
    ::MockTableSolver, 
    var::Int
)::Tuple{OptimalBranchingCore.BranchingTable, Vector{Int}}
    # Return empty table for var 1 (UNSAT), valid tables for others
    if var == 1
        return OptimalBranchingCore.BranchingTable(0, Vector{UInt64}[]), Int[]
    else
        # Return a simple valid branching table
        return OptimalBranchingCore.BranchingTable(1, [[0x0, 0x1]]), [var]
    end
end

function OptimalBranchingCore.optimal_branching_rule(
    ::OptimalBranchingCore.BranchingTable,
    variables::Vector{Int},
    ::TNProblem,
    ::OptimalBranchingCore.AbstractMeasure,
    ::MockSetCoverSolver
)
    var = first(variables)
    gamma = get(gamma_values, var, Inf)
    # Return a result with the gamma value
    # The actual structure depends on OptimalBranchingCore, but we need γ field
    return (γ=gamma, clauses=[[var]])
end

OptimalBranchingCore.get_clauses(result) = result.clauses

@testset "MinGammaSelector" begin
    problem = build_dummy_problem()
    selector = MinGammaSelector(MockTableSolver(), MockSetCoverSolver())
    chosen = OptimalBranchingCore.select_variables(problem, NumUnfixedVars(), selector)
    
    # Variable 2 has gamma 0.25, variable 3 has gamma 0.9
    # Variable 1 should be skipped (empty table)
    # So variable 2 should be selected
    @test chosen == 2
end
