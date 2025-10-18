using Test
using BooleanInference
using BooleanInference: setup_from_tensor_network, TNProblem, DynamicWorkspace, setup_problem, select_variables, get_cached_region, LeastOccurrenceSelector, NumUnfixedVars
using BooleanInference: Region, construct_region, slicing, tensor_unwrapping, DomainMask
using BooleanInference: DM_BOTH, DM_0, DM_1, has0, has1, is_fixed
using BooleanInference: contract_tensors, contract_region, TNContractionSolver
using BooleanInference: separate_fixed_free_boundary, construct_boundary_config, construct_inner_config
using BooleanInference: extract_inner_configs, combine_configs, handle_no_boundary_case
using BooleanInference: get_cached_region_contraction, clear_region_cache!
using OptimalBranchingCore: branching_table
using TropicalNumbers: Tropical
using ProblemReductions: Factoring, reduceto, CircuitSAT
using GenericTensorNetworks

@testset "Region constructor" begin
    region = Region(1, 
                    [1, 2],
                    [3, 4],
                    [1, 2])
        
    @test region.id == 1
    @test length(region.tensors) == 2
    @test length(region.inner_vars) == 2
    @test length(region.boundary_vars) == 2
end

@testset "tensor_unwrapping" begin
    # Test 2x2 tensor (2^1 = 2)
    @test_throws AssertionError tensor_unwrapping([1.0, 2.0, 3.0])  # not power of 2
    
    # Test 2-element vector (2^1)
    vec2 = [1.0, 2.0]
    t2 = tensor_unwrapping(vec2)
    @test size(t2) == (2,)
    @test t2[1] == 1.0
    @test t2[2] == 2.0
    
    # Test 4-element vector (2^2)
    vec4 = [1.0, 2.0, 3.0, 4.0]
    t4 = tensor_unwrapping(vec4)
    @test size(t4) == (2, 2)
    @test t4[1,1] == 1.0
    @test t4[2,1] == 2.0
    @test t4[1,2] == 3.0
    @test t4[2,2] == 4.0
    
    # Test 8-element vector (2^3)
    vec8 = collect(1.0:8.0)
    t8 = tensor_unwrapping(vec8)
    @test size(t8) == (2, 2, 2)
    @test length(t8) == 8
end

@testset "slice_tensor basic" begin
    # Test 1D tensor (single boolean variable)
    # one(Tropical{Float64}) = 0.0ₜ = satisfied
    # zero(Tropical{Float64}) = -Infₜ = unsatisfied
    T1 = one(Tropical{Float64})
    T0 = zero(Tropical{Float64})
    tensor1d = [T1, T0]  # Allows x=0, forbids x=1
    axis_vars = [1]
    
    # Allow both values - shape unchanged
    doms_both = [DM_BOTH]
    result = slicing(tensor1d, doms_both, axis_vars)
    @test length(result) == 2
    @test result == [T1, T0]
    
    # Allow only 0 - slice to single element
    doms_0 = [DM_0]
    result = slicing(tensor1d, doms_0, axis_vars)
    @test length(result) == 1  # Only 1 free variable value
    @test result[1] == T1  # x=0, keeps original value
    
    # Allow only 1 - slice to single element
    doms_1 = [DM_1]
    result = slicing(tensor1d, doms_1, axis_vars)
    @test length(result) == 1  # Only 1 free variable value
    @test result[1] == T0  # x=1, original was unsatisfied
end

@testset "slice_tensor 2D" begin
    # Test 2D tensor (two boolean variables)
    # tensor[i,j] represents variable assignment (i-1, j-1)
    # Using Tropical: one=satisfied, zero=unsatisfied
    T1 = one(Tropical{Float64})
    T0 = zero(Tropical{Float64})
    tensor2d = [T1, T1, T1, T0]  # (0,0), (1,0), (0,1), (1,1)
    axis_vars = [1, 2]
    
    # Allow both variables to take both values - shape unchanged
    doms = [DM_BOTH, DM_BOTH]
    result = slicing(tensor2d, doms, axis_vars)
    @test length(result) == 4
    @test result == [T1, T1, T1, T0]
    
    # Fix first variable to 0, allow second to vary - becomes 1D
    doms = [DM_0, DM_BOTH]
    result = slicing(tensor2d, doms, axis_vars)
    @test length(result) == 2  # Only x2 free: x2=0, x2=1
    @test result[1] == T1  # x1=0, x2=0
    @test result[2] == T1  # x1=0, x2=1
    
    # Fix second variable to 1, allow first to vary - becomes 1D
    doms = [DM_BOTH, DM_1]
    result = slicing(tensor2d, doms, axis_vars)
    @test length(result) == 2  # Only x1 free: x1=0, x1=1
    @test result[1] == T1  # x1=0, x2=1
    @test result[2] == T0  # x1=1, x2=1
    
    # Fix both variables to (0,1) - becomes scalar
    doms = [DM_0, DM_1]
    result = slicing(tensor2d, doms, axis_vars)
    @test length(result) == 1  # No free variables
    @test result[1] == T1  # x1=0, x2=1
end

@testset "slice_tensor 3D" begin
    # Test 3D tensor (three boolean variables)
    # Only use one and zero of Tropical
    T1 = one(Tropical{Float64})
    T0 = zero(Tropical{Float64})
    # Pattern: allow most, forbid some specific combinations
    # Index order: (x1,x2,x3) = (0,0,0), (1,0,0), (0,1,0), (1,1,0), (0,0,1), (1,0,1), (0,1,1), (1,1,1)
    tensor3d = [T1, T1, T0, T1, T1, T0, T1, T0]
    axis_vars = [1, 2, 3]
    
    # Allow all - shape unchanged
    doms = [DM_BOTH, DM_BOTH, DM_BOTH]
    result = slicing(tensor3d, doms, axis_vars)
    @test length(result) == 8
    @test result == tensor3d
    
    # Fix x1=1 and x3=0, allow x2 to vary - becomes 1D
    doms = [DM_1, DM_BOTH, DM_0]
    result = slicing(tensor3d, doms, axis_vars)
    @test length(result) == 2  # Only x2 free: x2=0, x2=1
    # x1=1, x2=0, x3=0 -> index 010 binary (bit pattern) = index 2 (0-indexed) = tensor3d[2] = T1
    # x1=1, x2=1, x3=0 -> index 110 binary = index 6 (0-indexed) = tensor3d[7] = T1
    @test result[1] == T1  # x1=1, x2=0, x3=0
    @test result[2] == T1  # x1=1, x2=1, x3=0
    
    # Fix all variables - becomes scalar
    doms = [DM_0, DM_1, DM_1]
    result = slicing(tensor3d, doms, axis_vars)
    @test length(result) == 1  # No free variables
    # x1=0, x2=1, x3=1 -> index 011 reversed = 110 binary = index 6 (0-indexed) = tensor3d[7] = T1
    @test result[1] == T1
end

@testset "DomainMask helpers" begin
    @test has0(DM_BOTH) == true
    @test has1(DM_BOTH) == true
    @test has0(DM_0) == true
    @test has1(DM_0) == false
    @test has0(DM_1) == false
    @test has1(DM_1) == true
end

function AND_test()
    T1 = one(Tropical{Float64})
    T0 = zero(Tropical{Float64})

    # T[x1, x2, y]
    T_and = Array{Tropical{Float64}}(undef, 2, 2, 2)

    for x1 in 0:1, x2 in 0:1, y in 0:1
        if y == (x1 & x2)
            T_and[x1+1, x2+1, y+1] = T1
        else
            T_and[x1+1, x2+1, y+1] = T0
        end
    end
    return T_and
end

function NOT_test()
    T0 = zero(Tropical{Float64})
    T1 = one(Tropical{Float64})
    T_not = Array{Tropical{Float64}}(undef, 2, 2)
    for x in 0:1, y in 0:1
        if y != x
            T_not[x+1, y+1] = T1
        else
            T_not[x+1, y+1] = T0
        end
    end
    return T_not
end

@testset "contract_tensors" begin
    tensor1 = AND_test()
    vector1 = vec(tensor1)
    DOMs = DomainMask[DM_BOTH, DM_BOTH, DM_0]
    sliced_tensor1 = slicing(vector1, DOMs, [1, 2, 3])
    reshaped_tensor1 = tensor_unwrapping(sliced_tensor1)

    tensor2 = NOT_test()
    vector2 = vec(tensor2)
    DOMs = DomainMask[DM_BOTH, DM_BOTH]
    sliced_tensor2 = slicing(vector2, DOMs, [1, 2])
    @test size(sliced_tensor2) == size(vector2)

    result = contract_tensors([sliced_tensor1, sliced_tensor2], Vector{Int}[Int[1,2], Int[4,2]], Int[1,2,4])
    @test result[2,2,1] == zero(Tropical{Float64})
end

function generate_example_problem(n::Int = 12)
    fproblem = Factoring(n, n, 6)
    res = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(res.circuit.circuit; use_constraints=true)
    return problem
end

@testset "contract_region" begin
    problem = generate_example_problem()
    tn = GenericTensorNetwork(problem)
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
    select_variables(tn_problem, NumUnfixedVars(), LeastOccurrenceSelector(2, 5))
    region = get_cached_region(tn_problem)
    @show region
    @test region != nothing
    @test isnothing(get_cached_region_contraction(tn_problem))

    contracted, _ = contract_region(tn_static, region, tn_problem.doms)
    @test contracted != nothing
    @test length(size(contracted)) == length(region.boundary_vars) + length(region.inner_vars)

    table = branching_table(tn_problem, TNContractionSolver(), vcat([v for v in region.boundary_vars], [v for v in region.inner_vars]))
    @show vcat([v for v in region.boundary_vars], [v for v in region.inner_vars])
    @show table

    cached_contraction = get_cached_region_contraction(tn_problem)
    @test !isnothing(cached_contraction)

    clear_region_cache!(tn_problem)
    @test isnothing(get_cached_region(tn_problem))
    @test isnothing(get_cached_region_contraction(tn_problem))
end


using BooleanInference: separate_fixed_free_boundary
@testset "separate_fixed_free_boundary" begin
    region = Region(1,
                    [1, 2],
                    [5, 6],
                    [3, 4])
    
    doms = fill(DM_BOTH, 10)
    fixed, fixed_vals, free, free_indices = separate_fixed_free_boundary(region, doms)
    @test isempty(fixed)
    @test isempty(fixed_vals)
    @test length(free) == 2
    @test free == Int[3, 4]
    @test free_indices == [1, 2]
    
    doms[3] = DM_0
    doms[4] = DM_1
    fixed, fixed_vals, free, free_indices = separate_fixed_free_boundary(region, doms)
    @test length(fixed) == 2
    @test fixed == Int[3, 4]
    @test fixed_vals == Int[0, 1]
    @test isempty(free)
    @test isempty(free_indices)
    
    doms[3] = DM_0
    doms[4] = DM_BOTH
    fixed, fixed_vals, free, free_indices = separate_fixed_free_boundary(region, doms)
    @test length(fixed) == 1
    @test fixed == Int[3]
    @test fixed_vals == Int[0]
    @test length(free) == 1
    @test free == Int[4]
    @test free_indices == [2]
end

using BooleanInference: construct_boundary_config
@testset "construct_boundary_config" begin
    region = Region(1,
                    [1],
                    [5],
                    [3, 4])
    
    doms = fill(DM_BOTH, 10)
    free_boundary_indices = [1, 2]
    
    config = construct_boundary_config(region, doms, free_boundary_indices, 0)
    @test config == [false, false]
    
    config = construct_boundary_config(region, doms, free_boundary_indices, 1)
    @test config == [true, false]
    
    config = construct_boundary_config(region, doms, free_boundary_indices, 2)
    @test config == [false, true]
    
    config = construct_boundary_config(region, doms, free_boundary_indices, 3)
    @test config == [true, true]
    
    doms[3] = DM_1
    free_boundary_indices = [2]
    
    config = construct_boundary_config(region, doms, free_boundary_indices, 0)
    @test config == [true, false]
    
    config = construct_boundary_config(region, doms, free_boundary_indices, 1)
    @test config == [true, true]
end

using BooleanInference: extract_inner_configs
@testset "extract_inner_configs" begin
    T0 = zero(Tropical{Float64})
    T1 = one(Tropical{Float64})
    
    contracted_1d = reshape([T1, T0], 2)
    configs = extract_inner_configs(contracted_1d, 1)
    @test length(configs) == 1
    @test configs[1] == [false]
    
    contracted_2d = reshape([T1, T0, T1, T1], 2, 2)
    configs = extract_inner_configs(contracted_2d, 2)
    @test length(configs) == 3
    @test [false, false] in configs
    @test [false, true] in configs
    @test [true, true] in configs
    @test !([true, false] in configs)
    
    contracted_3d = reshape([T1, T1, T1, T1, T1, T1, T1, T1], 2, 2, 2)
    configs = extract_inner_configs(contracted_3d, 3)
    @test length(configs) == 8
end

using BooleanInference: construct_inner_config
@testset "construct_inner_config" begin
    region = Region(1,
                    [1],
                    [5, 6, 7],
                    [3])
    
    doms = fill(DM_BOTH, 10)
    inner_var_ids = Int[5, 6, 7]
    free_inner_configs = [[false, false, false], [true, false, true]]
    
    inner_configs = construct_inner_config(region, doms, inner_var_ids, free_inner_configs)
    @test length(inner_configs) == 2
    @test inner_configs[1] == [false, false, false]
    @test inner_configs[2] == [true, false, true]
    
    doms[5] = DM_1
    inner_var_ids = Int[6, 7]
    free_inner_configs = [[false, false], [false, true]]
    
    inner_configs = construct_inner_config(region, doms, inner_var_ids, free_inner_configs)
    @test length(inner_configs) == 2
    @test inner_configs[1] == [true, false, false]
    @test inner_configs[2] == [true, false, true]
    
    doms[6] = DM_0
    inner_var_ids = Int[7]
    free_inner_configs = [[false], [true]]
    
    inner_configs = construct_inner_config(region, doms, inner_var_ids, free_inner_configs)
    @test length(inner_configs) == 2
    @test inner_configs[1] == [true, false, false]
    @test inner_configs[2] == [true, false, true]
end

using BooleanInference: combine_configs
@testset "combine_configs" begin
    boundary_config = [true, false]
    inner_configs = [[false, true], [true, false]]
    
    full_configs = combine_configs(boundary_config, inner_configs)
    @test length(full_configs) == 2
    @test full_configs[1] == [true, false, false, true]
    @test full_configs[2] == [true, false, true, false]
    
    boundary_config = [true]
    inner_configs = [[false]]
    
    full_configs = combine_configs(boundary_config, inner_configs)
    @test length(full_configs) == 1
    @test full_configs[1] == [true, false]
    
    boundary_config = Bool[]
    inner_configs = [[true, true], [false, false]]
    
    full_configs = combine_configs(boundary_config, inner_configs)
    @test length(full_configs) == 2
    @test full_configs[1] == [true, true]
    @test full_configs[2] == [false, false]
end
