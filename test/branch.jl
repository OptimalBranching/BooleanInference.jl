using Test
using BooleanInference
using BooleanInference: TNProblem, TNContractionSolver, MostOccurrenceSelector, NumUnfixedVars, setup_from_tensor_network, setup_problem, select_variables, get_var_value, bits_to_int, branch_and_reduce!, Result
using BooleanInference: BranchingStrategy, NoReducer
using ProblemReductions: Factoring, reduceto, CircuitSAT, read_solution, @circuit, Assignment, BooleanExpr
using GenericTensorNetworks
using GenericTensorNetworks: ∧, ∨, ¬
using OptimalBranchingCore

@testset "branch" begin
    fproblem = Factoring(10, 10, 559619)

    circuit_sat = reduceto(CircuitSAT, fproblem)
    problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)

    tn = GenericTensorNetwork(problem)
    tn_static = setup_from_tensor_network(tn)
    tn_problem = TNProblem(tn_static)
    br_strategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = MostOccurrenceSelector(1,2), measure = NumUnfixedVars())
    @time result = branch_and_reduce!(tn_problem, br_strategy, NoReducer(), Result; show_progress=false)
    @show result.stats
    if result.found
        @test !isnothing(result.solution)
        @test count_unfixed(result.solution) == 0
        a = get_var_value(result.solution, circuit_sat.q)
        b = get_var_value(result.solution, circuit_sat.p)
        @test bits_to_int(a) * bits_to_int(b) == 559619
    end
end


@testset "example" begin
    circuit = @circuit begin
        g1 = a ∧ b
        g3 = g1 ∧ d
        g2 = b ⊻ c
        g4 = ¬ (g2 ∧ e)
        out = g3 ∧ g4
    end
    push!(circuit.exprs, Assignment([:out],BooleanExpr(false)))
    tnproblem = setup_from_circuit(circuit)
    @show tnproblem.static.tensors[1]
    @show tnproblem.static.tensors[2]
    region = Region(1, [1,2], [2,3,4,5])
    @show tnproblem.doms

    contract = BooleanInference.contract_tensors([tnproblem.static.tensors[1].tensor,tnproblem.static.tensors[2].tensor], [tnproblem.static.tensors[1].var_axes, tnproblem.static.tensors[2].var_axes], [2,3,4,5])
    configs = map(BooleanInference.packint, findall(isone, contract))

    feasible_configs = BooleanInference.filter_feasible_configs(tnproblem, region, configs)
    table = BranchingTable(length(region.vars), [[c] for c in feasible_configs])
    @show table
    result = OptimalBranchingCore.optimal_branching_rule(table, region.vars, tnproblem, NumHardTensors(), GreedyMerge())
    @show result
    clauses = OptimalBranchingCore.get_clauses(result)
    @show [tnproblem.propagated_cache[clauses[i]] for i in 1:length(clauses)]
end