using Test
using BooleanInference
using BooleanInference: setup_problem, propagate, has_contradiction, init_doms, SolverBuffer
using BooleanInference: DM_NONE, DM_0, DM_1, DM_BOTH, is_fixed, has0, has1

@testset "propagate" begin
    @testset "Simple AND gate - full propagation" begin
        # AND gate: only (1,1) is feasible
        # BitVector layout: [00, 10, 01, 11] = [false, false, false, true]
        tensor_data = BitVector([false, false, false, true])

        static = setup_problem(2, [[1, 2]], [tensor_data]; precontract=false)
        buffer = SolverBuffer(static)

        # Initially both variables are unfixed
        doms = init_doms(static)
        @test doms[1] == DM_BOTH
        @test doms[2] == DM_BOTH

        # After propagation, both should be fixed to 1
        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test propagated[1] == DM_1
        @test propagated[2] == DM_1
        @test !has_contradiction(propagated)
    end

    @testset "OR gate - no propagation" begin
        # OR gate: (0,0) is infeasible, others are feasible
        # BitVector layout: [00, 10, 01, 11] = [false, true, true, true]
        tensor_data = BitVector([false, true, true, true])

        static = setup_problem(2, [[1, 2]], [tensor_data]; precontract=false)
        buffer = SolverBuffer(static)

        doms = init_doms(static)

        # No propagation should occur - multiple solutions
        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test propagated[1] == DM_BOTH
        @test propagated[2] == DM_BOTH
        @test !has_contradiction(propagated)
    end

    @testset "Propagation after partial assignment" begin
        # Implication: x1 → x2 (NOT x1 OR x2)
        # Table: (0,0)=true, (1,0)=false, (0,1)=true, (1,1)=true
        # BitVector layout: [00, 10, 01, 11] = [true, false, true, true]
        tensor_data = BitVector([true, false, true, true])

        static = setup_problem(2, [[1, 2]], [tensor_data]; precontract=false)
        buffer = SolverBuffer(static)

        # Fix x1 = 1
        doms = init_doms(static)
        doms[1] = DM_1

        # Propagation should fix x2 = 1 (since x1=1 and x1→x2)
        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test propagated[1] == DM_1
        @test propagated[2] == DM_1
        @test !has_contradiction(propagated)
    end

    @testset "Contradiction detection" begin
        # AND gate with initial contradiction: x1 must be 0 but AND requires both 1
        tensor_data = BitVector([false, false, false, true])  # AND: only (1,1)

        static = setup_problem(2, [[1, 2]], [tensor_data]; precontract=false)
        buffer = SolverBuffer(static)

        # Fix x1 = 0 (contradicts the AND constraint)
        doms = init_doms(static)
        doms[1] = DM_0

        # Propagation should detect contradiction
        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test has_contradiction(propagated)
    end

    @testset "Chain propagation - equality constraints" begin
        # Two equality constraints: x1 = x2, x2 = x3
        # Equality: (0,0)=true, (1,0)=false, (0,1)=false, (1,1)=true
        eq_tensor = BitVector([true, false, false, true])

        static = setup_problem(3, [[1, 2], [2, 3]], [eq_tensor, eq_tensor]; precontract=false)
        buffer = SolverBuffer(static)

        # Fix x1 = 1
        doms = init_doms(static)
        doms[1] = DM_1

        # Propagation should fix x2 = 1 and x3 = 1
        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test propagated[1] == DM_1
        @test propagated[2] == DM_1
        @test propagated[3] == DM_1
        @test !has_contradiction(propagated)
    end

    @testset "XOR constraint - no immediate propagation" begin
        # XOR: exactly one of x1, x2 must be true
        # Table: (0,0)=false, (1,0)=true, (0,1)=true, (1,1)=false
        xor_tensor = BitVector([false, true, true, false])

        static = setup_problem(2, [[1, 2]], [xor_tensor]; precontract=false)
        buffer = SolverBuffer(static)

        doms = init_doms(static)

        # No propagation without initial assignment
        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test propagated[1] == DM_BOTH
        @test propagated[2] == DM_BOTH
    end

    @testset "XOR with partial assignment" begin
        # XOR with x1 fixed to 1 should propagate x2 = 0
        xor_tensor = BitVector([false, true, true, false])

        static = setup_problem(2, [[1, 2]], [xor_tensor]; precontract=false)
        buffer = SolverBuffer(static)

        doms = init_doms(static)
        doms[1] = DM_1

        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test propagated[1] == DM_1
        @test propagated[2] == DM_0
        @test !has_contradiction(propagated)
    end

    @testset "Unit literal - single variable tensor" begin
        # Single variable constraint: x1 must be 1
        # BitVector layout: [0, 1] = [false, true]
        unit_tensor = BitVector([false, true])

        static = setup_problem(1, [[1]], [unit_tensor]; precontract=false)
        buffer = SolverBuffer(static)

        doms = init_doms(static)

        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test propagated[1] == DM_1
        @test !has_contradiction(propagated)
    end

    @testset "Empty initial touched - no propagation" begin
        tensor_data = BitVector([false, false, false, true])

        static = setup_problem(2, [[1, 2]], [tensor_data]; precontract=false)
        buffer = SolverBuffer(static)

        doms = init_doms(static)

        # Empty touched list should not trigger any propagation
        propagated = propagate(static, doms, Int[], buffer)
        @test propagated[1] == DM_BOTH
        @test propagated[2] == DM_BOTH
    end

    @testset "Multiple tensors with shared variables" begin
        # x1 AND x2 = 1, x2 AND x3 = 1
        and_tensor = BitVector([false, false, false, true])

        static = setup_problem(3, [[1, 2], [2, 3]], [and_tensor, and_tensor]; precontract=false)
        buffer = SolverBuffer(static)

        doms = init_doms(static)

        # Initial propagation should fix all to 1
        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test propagated[1] == DM_1
        @test propagated[2] == DM_1
        @test propagated[3] == DM_1
        @test !has_contradiction(propagated)
    end

    @testset "Contradiction from conflicting constraints" begin
        # x1 must be 1 (from first tensor), x1 must be 0 (from second tensor)
        must_be_1 = BitVector([false, true])
        must_be_0 = BitVector([true, false])

        static = setup_problem(1, [[1], [1]], [must_be_1, must_be_0]; precontract=false)
        buffer = SolverBuffer(static)

        doms = init_doms(static)

        propagated = propagate(static, doms, collect(1:length(static.tensors)), buffer)
        @test has_contradiction(propagated)
    end
end

@testset "domain operations" begin
    @testset "is_fixed" begin
        @test is_fixed(DM_0) == true
        @test is_fixed(DM_1) == true
        @test is_fixed(DM_BOTH) == false
        @test is_fixed(DM_NONE) == false
    end

    @testset "has0 and has1" begin
        @test has0(DM_0) == true
        @test has0(DM_1) == false
        @test has0(DM_BOTH) == true
        @test has0(DM_NONE) == false

        @test has1(DM_0) == false
        @test has1(DM_1) == true
        @test has1(DM_BOTH) == true
        @test has1(DM_NONE) == false
    end

    @testset "has_contradiction" begin
        @test has_contradiction([DM_0, DM_1, DM_BOTH]) == false
        @test has_contradiction([DM_NONE, DM_1]) == true
        @test has_contradiction([DM_0, DM_NONE]) == true
    end
end