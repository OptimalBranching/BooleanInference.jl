using Test
using BooleanInference
using BooleanInference: setup_from_sat, TNProblem, solve, BranchingStrategy, TNContractionSolver,
    MostOccurrenceSelector, NumUnfixedVars, NoReducer, get_var_value, bits_to_int,
    bounded_ve_canonicalize, ConstraintNetwork, count_unfixed
using OptimalBranchingCore: GreedyMerge
import ProblemReductions: CircuitSAT, Factoring, reduceto

# Minimal coverage for the bounded-VE canonicalizer (M1) wired into the solver with protected
# read-out variables (M3): canonicalizing must preserve satisfiability, keep protected (factor-bit)
# variables alive, shrink the branch set, and let the factors be read straight off the solution.
@testset "bounded_ve_canonicalize + protected read-out" begin
    N = 31 * 29
    red = reduceto(CircuitSAT, Factoring(5, 5, N))
    sat = CircuitSAT(red.circuit.circuit; use_constraints=true)
    base = setup_from_sat(sat)
    o2n = base.static.orig_to_new
    q_orig = collect(red.q); p_orig = collect(red.p)

    # protected = factor-bit variables, in base-network id space (never eliminated)
    prot = Int[o2n[v] for v in vcat(q_orig, p_orig) if o2n[v] != 0]
    @test !isempty(prot)

    cn = bounded_ve_canonicalize(base.static; budget_B=6, protected=prot)
    @test cn isa ConstraintNetwork

    # M1: elimination actually happened — the branch set is strictly smaller.
    @test length(cn.vars) < length(base.static.vars)

    # M3: every protected factor-bit variable survives into the reduced network.
    for v in vcat(q_orig, p_orig)
        o2n[v] == 0 && continue
        @test cn.orig_to_new[v] != 0
    end

    # Solve the reduced network (cadical-free path) and read factors directly off the solution.
    strat = BranchingStrategy(table_solver=TNContractionSolver(),
        selector=MostOccurrenceSelector(1, 2), measure=NumUnfixedVars(),
        set_cover_solver=GreedyMerge())
    res = solve(TNProblem(cn), strat, NoReducer())
    @test res.found
    @test count_unfixed(res.solution) == 0

    qb = Bool[get_var_value(res.solution, cn.orig_to_new[v]) == 1 for v in q_orig]
    pb = Bool[get_var_value(res.solution, cn.orig_to_new[v]) == 1 for v in p_orig]
    a, b = bits_to_int(qb), bits_to_int(pb)
    @test a * b == N   # factors read with NO variable-elimination back-substitution
end
