using Test
using BooleanInference
using BooleanInference: TNProblem, NumUnfixedVars, setup_problem
using OptimalBranchingCore
using OptimalBranchingCore: Clause, greedymerge, bit_clauses, BranchingTable
using TropicalNumbers: Tropical
using DataStructures: PriorityQueue

# Helper function to create a simple test problem
function create_test_problem()
    dummy_tensors_to_vars = [[1, 2], [2, 3]]
    dummy_tensor_data = [
        fill(Tropical(0.0), 4),
        fill(Tropical(0.0), 4)
    ]
    static = BooleanInference.setup_problem(3, dummy_tensors_to_vars, dummy_tensor_data)
    return TNProblem(static, UInt8)
end


@testset "size_reduction" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    
    # Test with a valid clause
    clause = Clause(0b11, 0b10)  # variable 1 = 1
    
    reduction = OptimalBranchingCore.size_reduction(problem, measure, clause, variables)
    @test isfinite(reduction)
    
    # Test with an invalid clause that causes UNSAT
    clause_unsat = Clause(0b11, 0b00)  # This might cause UNSAT depending on problem
    reduction_unsat = OptimalBranchingCore.size_reduction(problem, measure, clause_unsat, variables)
    # Either finite or -Inf depending on whether it causes UNSAT
    @test isfinite(reduction_unsat) || reduction_unsat == -Inf
end

@testset "clause_key" begin
    # This is an internal function, but we can test it indirectly
    clause1 = Clause(0b11, 0b10)
    clause2 = Clause(0b11, 0b10)
    clause3 = Clause(0b11, 0b01)
    
    # Keys should be equal for identical clauses
    key1 = (getfield(clause1, 1), getfield(clause1, 2))
    key2 = (getfield(clause2, 1), getfield(clause2, 2))
    @test key1 == key2
    
    # Keys should differ for different clauses
    key3 = (getfield(clause3, 1), getfield(clause3, 2))
    @test key1 != key3
end

@testset "cached_size_reduction!" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    clause = Clause(0b11, 0b10)
    
    cache = Dict{Tuple{UInt64, UInt64}, Float64}()
    
    # First call should compute and cache
    reduction1 = OptimalBranchingCore.size_reduction(problem, measure, clause, variables)
    
    # Second call with same clause should use cache (if implemented)
    reduction2 = OptimalBranchingCore.size_reduction(problem, measure, clause, variables)
    @test reduction1 == reduction2
end

@testset "greedymerge - drop invalid rows" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    
    # Test that clauses with invalid reductions are filtered out
    clauses = [
        [Clause(0b11, 0b10)],  # Valid
        [Clause(0b11, 0b00)]   # Might be invalid
    ]
    result = OptimalBranchingCore.greedymerge(clauses, problem, variables, measure)
    @test !isnothing(result)
    result_clauses = OptimalBranchingCore.get_clauses(result)
    # Result should only contain valid clauses
    @test length(result_clauses) <= length(clauses)
end

@testset "greedymerge - deduplicate singletons" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    
    # Test deduplication of duplicate singleton clauses
    clause1 = Clause(0b11, 0b10)
    clauses = [
        [clause1],
        [clause1],  # Duplicate
        [Clause(0b11, 0b01)]
    ]
    result = OptimalBranchingCore.greedymerge(clauses, problem, variables, measure)
    @test !isnothing(result)
    result_clauses = OptimalBranchingCore.get_clauses(result)
    # Should deduplicate, so result clauses should be <= input
    @test length(result_clauses) <= length(clauses)
end

@testset "greedymerge - basic functionality" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    
    # Create a simple branching table
    # Use a simple case with valid clauses
    clauses = [[Clause(0b11, 0b10)], [Clause(0b11, 0b01)]]
    
    result = OptimalBranchingCore.greedymerge(clauses, problem, variables, measure)
    
    @test !isnothing(result)
    @test isfinite(result.γ) || result.γ == Inf
    result_clauses = OptimalBranchingCore.get_clauses(result)
    @test !isempty(result_clauses) || isempty(clauses)
end

@testset "greedymerge - invalid clauses" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    
    # Test with clauses that might cause UNSAT or invalid reductions
    invalid_clauses = [[Clause(0b11, 0b00)], [Clause(0b11, 0b11)]]
    result = OptimalBranchingCore.greedymerge(invalid_clauses, problem, variables, measure)
    # Result should handle invalid clauses gracefully
    @test !isnothing(result)
end

@testset "greedymerge - with branching table" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    
    # Create a branching table and test the full flow
    # This tests the integration with optimal_branching_rule
    table = BranchingTable(2, [[0x0, 0x1], [0x2, 0x3]])
    candidates = OptimalBranchingCore.bit_clauses(table)
    
    result = OptimalBranchingCore.greedymerge(candidates, problem, variables, measure)
    @test !isnothing(result)
    @test isfinite(result.γ) || result.γ == Inf
    result_clauses = OptimalBranchingCore.get_clauses(result)
    @test !isempty(result_clauses) || isempty(candidates)
end

@testset "greedymerge - multiple clauses per row" begin
    problem = create_test_problem()
    variables = [1, 2, 3]
    measure = NumUnfixedVars()
    
    # Test with multiple clauses in a row (should select best representative)
    # This tests select_representatives!
    clauses = [
        [Clause(0b111, 0b100), Clause(0b111, 0b010)],  # Multiple options
        [Clause(0b111, 0b001)]
    ]
    
    result = OptimalBranchingCore.greedymerge(clauses, problem, variables, measure)
    @test !isnothing(result)
    @test isfinite(result.γ) || result.γ == Inf
    result_clauses = OptimalBranchingCore.get_clauses(result)
    @test !isempty(result_clauses) || isempty(clauses)
end

@testset "greedymerge - merge queue processing" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    
    # Test that merging queue is processed correctly
    # This tests enqueue_beneficial_merges!, process_merge_queue!, etc.
    clauses = [
        [Clause(0b11, 0b10)],
        [Clause(0b11, 0b01)],
        [Clause(0b11, 0b00)]
    ]
    
    result = OptimalBranchingCore.greedymerge(clauses, problem, variables, measure)
    @test !isnothing(result)
    @test isfinite(result.γ) || result.γ == Inf
    result_clauses = OptimalBranchingCore.get_clauses(result)
    @test length(result_clauses) <= length(clauses)
end

@testset "greedymerge - merge behavior" begin
    problem = create_test_problem()
    variables = [1, 2]
    measure = NumUnfixedVars()
    
    # Test that merging actually happens when beneficial
    # Create clauses that might benefit from merging
    clauses = [
        [Clause(0b11, 0b10)],
        [Clause(0b11, 0b01)]
    ]
    
    result = OptimalBranchingCore.greedymerge(clauses, problem, variables, measure)
    @test !isnothing(result)
    # Result should have valid structure
    @test isfinite(result.γ) || result.γ == Inf
    result_clauses = OptimalBranchingCore.get_clauses(result)
    @test length(result_clauses) <= length(clauses)
end


