using Test
using BooleanInference
using BooleanInference: TNProblem, setup_problem, select_variables, MostOccurrenceSelector, NumUnfixedVars
using BooleanInference: Region, slicing, DomainMask, BoolTensor
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

@testset "slice_tensor basic" begin
    # Test 1D tensor (single boolean variable)
    T1 = one(Tropical{Float64})
    T0 = zero(Tropical{Float64})
    tensor1d_data = [T1, T0]  # Allows x=0, forbids x=1
    tensor1d = BoolTensor([1], tensor1d_data)

    # Allow both values - 2D output with 1 dimension
    doms_both = [DM_BOTH]
    result = slicing(tensor1d, doms_both)
    @test length(result) == 2
    @test vec(result) == [T1, T0]

    # Allow only 0 - scalar output
    doms_0 = [DM_0]
    result = slicing(tensor1d, doms_0)
    @test length(result) == 1
    @test result[1] == T1  # x=0

    # Allow only 1 - scalar output
    doms_1 = [DM_1]
    result = slicing(tensor1d, doms_1)
    @test length(result) == 1
    @test result[1] == T0  # x=1
end

@testset "slice_tensor 2D" begin
    T1 = one(Tropical{Float64})
    T0 = zero(Tropical{Float64})
    tensor2d_data = [T1, T1, T1, T0]  # (0,0), (1,0), (0,1), (1,1)
    tensor2d = BoolTensor([1, 2], tensor2d_data)

    # Allow both variables - 2×2 output
    doms = [DM_BOTH, DM_BOTH]
    result = slicing(tensor2d, doms)
    @test size(result) == (2, 2)
    @test vec(result) == [T1, T1, T1, T0]

    # Fix first variable to 0 - 1D output (second var free)
    doms = [DM_0, DM_BOTH]
    result = slicing(tensor2d, doms)
    @test size(result) == (2,)
    @test result[1] == T1  # x1=0, x2=0
    @test result[2] == T1  # x1=0, x2=1

    # Fix second variable to 1 - 1D output (first var free)
    doms = [DM_BOTH, DM_1]
    result = slicing(tensor2d, doms)
    @test size(result) == (2,)
    @test result[1] == T1  # x1=0, x2=1
    @test result[2] == T0  # x1=1, x2=1

    # Fix both variables - scalar output
    doms = [DM_0, DM_1]
    result = slicing(tensor2d, doms)
    @test length(result) == 1
    @test result[1] == T1  # x1=0, x2=1
end

@testset "slice_tensor 3D" begin
    T1 = one(Tropical{Float64})
    T0 = zero(Tropical{Float64})
    tensor3d_data = [T1, T1, T0, T1, T1, T0, T1, T0]
    tensor3d = BoolTensor([1, 2, 3], tensor3d_data)

    # Allow all - 2×2×2 output
    doms = [DM_BOTH, DM_BOTH, DM_BOTH]
    result = slicing(tensor3d, doms)
    @test size(result) == (2, 2, 2)
    @test vec(result) == tensor3d_data

    # Fix x1=1 and x3=0 - 1D output (x2 free)
    doms = [DM_1, DM_BOTH, DM_0]
    result = slicing(tensor3d, doms)
    @test size(result) == (2,)
    @test result[1] == T1  # x1=1, x2=0, x3=0
    @test result[2] == T1  # x1=1, x2=1, x3=0

    # Fix all variables - scalar
    doms = [DM_0, DM_1, DM_1]
    result = slicing(tensor3d, doms)
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
    # Create AND tensor: y = x1 & x2
    tensor1 = AND_test()
    vector1 = vec(tensor1)
    booltensor1 = BoolTensor([1, 2, 3], vector1)

    DOMs1 = DomainMask[DM_BOTH, DM_BOTH, DM_0]
    sliced_tensor1 = slicing(booltensor1, DOMs1)

    # Create NOT tensor: y = !x
    tensor2 = NOT_test()
    vector2 = vec(tensor2)
    booltensor2 = BoolTensor([1, 2], vector2)

    DOMs2 = DomainMask[DM_BOTH, DM_BOTH]
    sliced_tensor2 = slicing(booltensor2, DOMs2)
    @test size(sliced_tensor2) == (2, 2)

    result = contract_tensors([sliced_tensor1, sliced_tensor2], Vector{Int}[Int[1,2], Int[4,2]], Int[1,2,4])
    @test result[2,2,1] == zero(Tropical{Float64})
end

