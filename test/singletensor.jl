using Test
using BooleanInference
using OptimalBranchingCore

@testset "SingleTensorSolver" begin
    @testset "partition_tensor_variables" begin
        # Test with mixed fixed and unfixed variables
        doms = [DM_0, DM_BOTH, DM_1, DM_BOTH, DM_0]
        tensor_vars = [1, 2, 3, 4, 5]

        fixed_pos, unfixed_pos, unfixed_ids = partition_tensor_variables(tensor_vars, doms)

        @test length(fixed_pos) == 3
        @test (1, false) in fixed_pos  # var 1 fixed to 0
        @test (3, true) in fixed_pos   # var 3 fixed to 1
        @test (5, false) in fixed_pos  # var 5 fixed to 0

        @test unfixed_pos == [2, 4]
        @test unfixed_ids == [2, 4]
    end

    @testset "SingleTensorSolver basic test" begin
        # Create a problem with 3 variables and 2 tensors
        # Tensor 1: v1 OR v2 (has multiple satisfying assignments)
        # Tensor 2: v2 OR v3 (has multiple satisfying assignments)
        using TropicalNumbers

        # Tensor 1: v1 OR v2
        tensor1_data = [
            Tropical(Inf),  # (0,0) -> UNSAT
            Tropical(0.0),  # (0,1) -> SAT
            Tropical(0.0),  # (1,0) -> SAT
            Tropical(0.0)   # (1,1) -> SAT
        ]

        # Tensor 2: v2 OR v3
        tensor2_data = [
            Tropical(Inf),  # (0,0) -> UNSAT
            Tropical(0.0),  # (0,1) -> SAT
            Tropical(0.0),  # (1,0) -> SAT
            Tropical(0.0)   # (1,1) -> SAT
        ]

        # Use setup_problem to create BipartiteGraph
        static = setup_problem(3, [[1, 2], [2, 3]], [tensor1_data, tensor2_data])

        # Create problem (all variables unfixed initially)
        problem = TNProblem(static, verbose=false)

        # All variables should remain unfixed (multiple solutions possible)
        @test count_unfixed(problem) == 3

        # Test with SingleTensorSolver on tensor 1
        solver = SingleTensorSolver()
        table, variables = OptimalBranchingCore.branching_table(problem, solver, 1)

        @test !isempty(table.table)
        @test length(variables) == 2
        @test variables == [1, 2]

        # Should have 3 valid configurations: (0,1), (1,0), (1,1)
        @test length(table.table) == 1
        @test length(table.table[1]) == 3
        @test 0b01 in table.table[1]  # v1=0, v2=1
        @test 0b10 in table.table[1]  # v1=1, v2=0
        @test 0b11 in table.table[1]  # v1=1, v2=1
    end

    @testset "SingleTensorSolver with fixed variables" begin
        using TropicalNumbers

        # Create a problem with 3 variables and 2 tensors
        # Tensor 1: v1 OR v2
        # Tensor 2: v2 OR v3
        tensor1_data = [
            Tropical(Inf),  # (0,0) -> UNSAT
            Tropical(0.0),  # (0,1) -> SAT
            Tropical(0.0),  # (1,0) -> SAT
            Tropical(0.0)   # (1,1) -> SAT
        ]

        tensor2_data = [
            Tropical(Inf),  # (0,0) -> UNSAT
            Tropical(0.0),  # (0,1) -> SAT
            Tropical(0.0),  # (1,0) -> SAT
            Tropical(0.0)   # (1,1) -> SAT
        ]

        static = setup_problem(3, [[1, 2], [2, 3]], [tensor1_data, tensor2_data])

        # Manually fix v1 to 0 (without propagation)
        doms = [DM_0, DM_BOTH, DM_BOTH]
        problem = TNProblem(static, doms, 2, DynamicWorkspace(3, false))

        solver = SingleTensorSolver()
        table, variables = OptimalBranchingCore.branching_table(problem, solver, 1)

        # Tensor 1 has variables [1, 2], but v1 is fixed to 0
        @test length(variables) == 1
        @test variables == [2]

        # With v1=0, tensor 1 (v1 OR v2) requires v2=1 to be SAT
        @test length(table.table) == 1
        @test length(table.table[1]) == 1
        @test table.table[1][1] == 0b1  # v2=1
    end

    @testset "SingleTensorSolver UNSAT case" begin
        using TropicalNumbers

        # Create a tensor that's always UNSAT
        tensor_data = [
            Tropical(Inf),  # (0,0) -> UNSAT
            Tropical(Inf),  # (0,1) -> UNSAT
            Tropical(Inf),  # (1,0) -> UNSAT
            Tropical(Inf)   # (1,1) -> UNSAT
        ]

        # Add a second tensor to prevent immediate UNSAT detection
        tensor2_data = [
            Tropical(0.0),  # (0,0) -> SAT
            Tropical(0.0),  # (0,1) -> SAT
            Tropical(0.0),  # (1,0) -> SAT
            Tropical(0.0)   # (1,1) -> SAT
        ]

        static = setup_problem(3, [[1, 2], [2, 3]], [tensor_data, tensor2_data])

        # Manually create problem without propagation
        doms = [DM_BOTH, DM_BOTH, DM_BOTH]
        problem = TNProblem(static, doms, 3, DynamicWorkspace(3, false))

        solver = SingleTensorSolver()
        table, variables = OptimalBranchingCore.branching_table(problem, solver, 1)

        # Tensor 1 is always UNSAT, should return empty table
        @test isempty(table.table)
        @test isempty(variables)
    end
end
