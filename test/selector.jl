using Test
using BooleanInference
using BooleanInference: LeastOccurrenceSelector
using ProblemReductions: Factoring, reduceto, CircuitSAT
using GenericTensorNetworks
using BooleanInference: setup_from_tensor_network, TNProblem, DynamicWorkspace, NumUnfixedVars
using BooleanInference: get_cached_region, clear_region_cache!, clear_all_region_caches!, setup_from_cnf, k_neighboring
using OptimalBranchingCore: select_variables
using BooleanInference.GenericTensorNetworks: ∧, ∨, ¬
using BooleanInference.OptimalBranchingCore: select_variables, apply_branch, Clause

function generate_example_problem(n::Int = 12)
    fproblem = Factoring(n, n, 6)
    res = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(res.circuit.circuit; use_constraints=true)
    return problem
end

@testset "LeastOccurrenceSelector" begin
    selector = LeastOccurrenceSelector(1)
    @test selector.k == 1
    # Default max_tensors is 2
    @test selector.max_tensors == 2
    selector = LeastOccurrenceSelector(2, 20)
    @test selector.k == 2
    @test selector.max_tensors == 20
end

@testset "select_variables" begin
    problem = generate_example_problem()
    tn = GenericTensorNetwork(problem)
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
    selector = LeastOccurrenceSelector(1)
    select_variables(tn_problem, NumUnfixedVars(), selector)

    region = get_cached_region(tn_problem)
    first_var = region.id
    should_involved_tensors = tn_static.v2t[first_var]
    @test length(region.tensors) == length(should_involved_tensors)
    @test all(t in region.tensors for t in should_involved_tensors)
    @test length(region.inner_vars) == 1
    @test region.inner_vars[1] == first_var
    # After propagation, some boundary variables may be fixed
    # Check that all boundary variables in the region are unfixed and neighboring the focus var
    for v in region.boundary_vars
        @test !BooleanInference.is_fixed(tn_problem.doms[v])
    end
    # Check that focus variable is properly in inner vars
    @test first_var in region.inner_vars
end

@testset "clear_region_cache!" begin
    problem = generate_example_problem()
    tn = GenericTensorNetwork(problem)
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
    @test get_cached_region(tn_problem) == nothing
    select_variables(tn_problem, NumUnfixedVars(), LeastOccurrenceSelector(1))
    @test get_cached_region(tn_problem) != nothing
    
    problem2 = generate_example_problem()
    tn2 = GenericTensorNetwork(problem2)
    tn_static2 = setup_from_tensor_network(tn2)
    tn_problem2 = TNProblem(tn_static2)
    @test get_cached_region(tn_problem2) == nothing
    select_variables(tn_problem2, NumUnfixedVars(), LeastOccurrenceSelector(1))
    @test get_cached_region(tn_problem2) != nothing

    clear_region_cache!(tn_problem)
    @test get_cached_region(tn_problem) == nothing
    clear_all_region_caches!()
    @test get_cached_region(tn_problem) == nothing
    @test get_cached_region(tn_problem2) == nothing
end

@testset "KNeighborSelector" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c))
    problem = setup_from_cnf(cnf)
    # After initial propagation, some variables may be fixed
    # Use a larger max_tensors to include all tensors
    vars = select_variables(problem, NumUnfixedVars(), LeastOccurrenceSelector(4, 10))
    # After propagation, only unfixed variables are returned
    unfixed_vars = BooleanInference.get_unfixed_vars(problem.doms)
    @test vars == unfixed_vars

    region = get_cached_region(problem)
    # Check that the region contains tensors related to unfixed variables
    @test length(region.tensors) > 0
    @test region.boundary_vars == []
end