using Test
using BooleanInference
using BooleanInference: TNProblem, setup_problem, select_variables, MostOccurrenceSelector, NumUnfixedVars
using BooleanInference: Region, slicing, DomainMask
using BooleanInference: DM_BOTH, DM_0, DM_1, has0, has1, is_fixed
using BooleanInference: contract_tensors, contract_region, TNContractionSolver
using OptimalBranchingCore: branching_table
using TropicalNumbers: Tropical
using ProblemReductions: Factoring, reduceto, CircuitSAT
using GenericTensorNetworks

@testset "Region constructor" begin
    region = Region(1,
        [1, 2],
        [1, 2, 3, 4])

    @test region.id == 1
    @test length(region.tensors) == 2
    @test length(region.vars) == 4
end

@testset "slice_tensor basic via ConstraintNetwork" begin
    # Create a simple problem to test slicing through ConstraintNetwork API
    # Test 1D tensor (single boolean variable)
    # T1 = one(Tropical{Float64})
    # T0 = zero(Tropical{Float64})
    T1 = true; T0 = false

    # Create a simple problem: 1 variable, 1 tensor
    tensor_data = BitVector([true, false])  # Allows x=0, forbids x=1
    static = setup_problem(1, [[1]], [tensor_data])
    tensor = static.tensors[1]

    # Allow both values - 2D output with 1 dimension
    doms_both = DomainMask[DM_BOTH]
    result = slicing(static, tensor, doms_both)
    @test length(result) == 2
    @test result[1] == T1  # x=0 is satisfied (true -> T1)
    @test result[2] == T0  # x=1 is not satisfied (false -> T0)

    # Allow only 0 - scalar output
    doms_0 = DomainMask[DM_0]
    result = slicing(static, tensor, doms_0)
    @test length(result) == 1
    @test result[1] == T1  # x=0

    # Allow only 1 - scalar output
    doms_1 = DomainMask[DM_1]
    result = slicing(static, tensor, doms_1)
    @test length(result) == 1
    @test result[1] == T0  # x=1
end

@testset "slice_tensor 2D via ConstraintNetwork" begin
    T1 = true; T0 = false

    # Create a 2-variable problem
    # Tensor data: (0,0)=T1, (1,0)=T1, (0,1)=T1, (1,1)=T0
    tensor_data = BitVector([true, true, true, false])
    static = setup_problem(2, [[1, 2]], [tensor_data])
    tensor = static.tensors[1]

    # Allow both variables - 2×2 output
    doms = DomainMask[DM_BOTH, DM_BOTH]
    result = slicing(static, tensor, doms)
    @test size(result) == (2, 2)
    @test vec(result) == [T1, T1, T1, T0]

    # Fix first variable to 0 - 1D output (second var free)
    doms = DomainMask[DM_0, DM_BOTH]
    result = slicing(static, tensor, doms)
    @test size(result) == (2,)
    @test result[1] == T1  # x1=0, x2=0
    @test result[2] == T1  # x1=0, x2=1

    # Fix second variable to 1 - 1D output (first var free)
    doms = DomainMask[DM_BOTH, DM_1]
    result = slicing(static, tensor, doms)
    @test size(result) == (2,)
    @test result[1] == T1  # x1=0, x2=1
    @test result[2] == T0  # x1=1, x2=1

    # Fix both variables - scalar output
    doms = DomainMask[DM_0, DM_1]
    result = slicing(static, tensor, doms)
    @test length(result) == 1
    @test result[1] == T1  # x1=0, x2=1
end

@testset "slice_tensor 3D via ConstraintNetwork" begin
    T1 = true; T0 = false

    # 3-variable tensor
    tensor_data = BitVector([true, true, false, true, true, false, true, false])
    static = setup_problem(3, [[1, 2, 3]], [tensor_data])
    tensor = static.tensors[1]

    # Allow all - 2×2×2 output
    doms = DomainMask[DM_BOTH, DM_BOTH, DM_BOTH]
    result = slicing(static, tensor, doms)
    @test size(result) == (2, 2, 2)
    @test vec(result) == [T1, T1, T0, T1, T1, T0, T1, T0]

    # Fix x1=1 and x3=0 - 1D output (x2 free)
    doms = DomainMask[DM_1, DM_BOTH, DM_0]
    result = slicing(static, tensor, doms)
    @test size(result) == (2,)
    @test result[1] == T1  # x1=1, x2=0, x3=0
    @test result[2] == T1  # x1=1, x2=1, x3=0

    # Fix all variables - scalar
    doms = DomainMask[DM_0, DM_1, DM_1]
    result = slicing(static, tensor, doms)
    @test length(result) == 1
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

@testset "contract_tensors" begin
    T1 = true; T0 = false

    # Create AND tensor: y = x1 & x2
    # Manually create the tensor array for contraction testing
    T_and = Array{typeof(T1)}(undef, 2, 2, 2)
    for x1 in 0:1, x2 in 0:1, y in 0:1
        if y == (x1 & x2)
            T_and[x1+1, x2+1, y+1] = T1
        else
            T_and[x1+1, x2+1, y+1] = T0
        end
    end

    # Create NOT tensor: y = !x
    T_not = Array{typeof(T1)}(undef, 2, 2)
    for x in 0:1, y in 0:1
        if y != x
            T_not[x+1, y+1] = T1
        else
            T_not[x+1, y+1] = T0
        end
    end

    # Slice the AND tensor (fix output y=0)
    sliced_and = T_and[:, :, 1]  # Keep only y=0 configurations
    @test size(sliced_and) == (2, 2)

    # Contract tensors using the API
    result = contract_tensors([sliced_and, T_not], Vector{Int}[Int[1, 2], Int[4, 2]], Int[1, 2, 4])
    @test result[2, 2, 1] == T0
end
