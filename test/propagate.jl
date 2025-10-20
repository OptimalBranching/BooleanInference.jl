using Test
using BooleanInference
using TropicalNumbers
using BooleanInference: setup_from_cnf, propagate, has1, is_fixed, has0,setup_from_circuit
using ProblemReductions: @circuit, Assignment, BooleanExpr, Factoring, reduceto
using GenericTensorNetworks

@testset "propagate" begin
    # Test 1: Simple AND gate (x1 ∧ x2 = 1)
    # Only one feasible config: (1, 1)
    T1 = one(Tropical{Float64})
    T0 = zero(Tropical{Float64})
    @testset "Simple unit propagation - AND gate" begin
        # Create a 2-variable AND constraint
        # Tensor encodes: only (1,1) is feasible (Tropical(0.0))
        tensor_data = [
            T0,  # (0,0) - infeasible
            T0,  # (1,0) - infeasible
            T0,  # (0,1) - infeasible
            T1   # (1,1) - feasible
        ]
        
        static = BooleanInference.setup_problem(
            2,
            [[1, 2]],
            [tensor_data]
        )
        
        # Initially both variables are unfixed
        doms = BooleanInference.init_doms(static)
        @test doms[1] == BooleanInference.DM_BOTH
        @test doms[2] == BooleanInference.DM_BOTH
        
        # After propagation, both should be fixed to 1
        propagated = BooleanInference.propagate(static, doms)
        @test propagated[1] == BooleanInference.DM_1
        @test propagated[2] == BooleanInference.DM_1
    end
    
    # Test 2: No unit propagation possible
    @testset "No propagation - multiple solutions" begin
        # OR gate: (0,0) is infeasible, others are feasible
        tensor_data = [
            T0,  # (0,0) - infeasible
            T1,  # (1,0) - feasible
            T1,  # (0,1) - feasible
            T1   # (1,1) - feasible
        ]
        
        static = BooleanInference.setup_problem(
            2,
            [[1, 2]],
            [tensor_data]
        )
        
        doms = BooleanInference.init_doms(static)
        
        # No unit propagation should occur
        propagated = BooleanInference.propagate(static, doms)
        @test propagated[1] == BooleanInference.DM_BOTH
        @test propagated[2] == BooleanInference.DM_BOTH
    end
    
    # Test 3: Partial assignment leading to unit propagation
    @testset "Propagation after partial assignment" begin
        # AND gate again
        tensor_data = [
            T0,  # (0,0) - infeasible
            T0,  # (1,0) - infeasible
            T0,  # (0,1) - infeasible
            T1   # (1,1) - feasible
        ]
        
        static = BooleanInference.setup_problem(
            2,
            [[1, 2]],
            [tensor_data]
        )
        
        # Fix x1 = 1
        doms = BooleanInference.init_doms(static)
        doms[1] = BooleanInference.DM_1
        
        # Propagation should fix x2 = 1
        propagated = BooleanInference.propagate(static, doms)
        @test propagated[1] == BooleanInference.DM_1
        @test propagated[2] == BooleanInference.DM_1
    end
    
    # Test 4: Contradiction detection
    @testset "Contradiction detection" begin
        # AND gate with x1 = 0 should lead to contradiction
        tensor_data = [
            T0,  # (0,0) - infeasible
            T0,  # (1,0) - infeasible
            T0,  # (0,1) - infeasible
            T1   # (1,1) - feasible
        ]
        
        static = BooleanInference.setup_problem(
            2,
            [[1, 2]],
            [tensor_data]
        )
        
        # Fix x1 = 0 (contradicts the AND constraint)
        doms = BooleanInference.init_doms(static)
        doms[1] = BooleanInference.DM_0
        
        # Propagation should detect contradiction
        propagated = BooleanInference.propagate(static, doms)
        @test all(d -> d.bits == 0x00, propagated)
    end
    
    # Test 5: Chain propagation
    @testset "Chain propagation" begin
        # Two constraints: x1 = x2, x2 = x3
        # x1 = x2: (0,0) and (1,1) are feasible
        tensor1 = [
            T1,  # (0,0) - feasible
            T0,  # (1,0) - infeasible
            T0,  # (0,1) - infeasible
            T1   # (1,1) - feasible
        ]
        
        # x2 = x3: (0,0) and (1,1) are feasible
        tensor2 = [
            T1,  # (0,0) - feasible
            T0,  # (1,0) - infeasible
            T0,  # (0,1) - infeasible
            T1   # (1,1) - feasible
        ]
        
        static = BooleanInference.setup_problem(
            3,
            [[1, 2], [2, 3]],
            [tensor1, tensor2]
        )
        
        # Fix x1 = 1
        doms = BooleanInference.init_doms(static)
        doms[1] = BooleanInference.DM_1
        
        # Propagation should fix x2 = 1 and x3 = 1
        propagated = BooleanInference.propagate(static, doms)
        @test propagated[1] == BooleanInference.DM_1
        @test propagated[2] == BooleanInference.DM_1
        @test propagated[3] == BooleanInference.DM_1
    end
end

@testset "reduce_problem" begin
    @bools a b c d e f g
    cnf = ∧(∨(a, b, ¬d, ¬e), ∨(¬a, d, e, ¬f), ∨(f, g), ∨(¬b, c), ∨(¬a))
    problem = setup_from_cnf(cnf)
    new_doms = propagate(problem.static, problem.doms)
    @show new_doms[1]
    @test has0(new_doms[1]) && is_fixed(new_doms[1]) == true
    # TODO: undecided_literal has not been refactored yet

    @bools x1 x2 x3 x4 x5
    cnf = ∧(∨(x1), ∨(x2, ¬x3), ∨(x4, ¬x1), ∨(¬x3, ¬x4), ∨(x2, x5), ∨(x2, x5, ¬x3))
    problem = setup_from_cnf(cnf)
    new_doms = propagate(problem.static, problem.doms)
    # TODO: undecided_literal has not been refactored yet

    circuit = @circuit begin
        c = x ∧ y
    end
    push!(circuit.exprs, Assignment([:c], BooleanExpr(true)))
    problem = setup_from_circuit(circuit)
    new_doms = propagate(problem.static, problem.doms)
    @show new_doms
end