function cnf2bip(cnf::CNF)
    return sat2bip(Satisfiability(cnf))
end

function sat2bip(sat::ConstraintSatisfactionProblem)
    problem = GenericTensorNetwork(sat)
    he2v = getixsv(problem.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), problem)
    vec_tensors = [vec(t) for t in tensors]
    new_tensors = [replace(t,Tropical(1.0) => zero(Tropical{Float64})) for t in vec_tensors]
    return BooleanInferenceProblem(new_tensors, he2v, length(problem.problem.symbols)), problem.problem.symbols
end

function cir2bip(cir::Circuit)
    return sat2bip(CircuitSAT(cir))
end

function solvesat(sat::ConstraintSatisfactionProblem; bsconfig::BranchingStrategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = KNeighborSelector(1,1), measure=NumOfVertices()), reducer=NoReducer())
    p,syms = sat2bip(sat)
    return solvebip(p; bsconfig, reducer)
end

function solve_factoring(n::Int, m::Int, N::Int; bsconfig::BranchingStrategy = BranchingStrategy(table_solver = TNContractionSolver(), selector =KNeighborSelector(1,1), measure=NumOfVertices()), reducer=NoReducer())
    # global BRANCHNUMBER = 0
    fproblem = Factoring(m, n, N)
    res = reduceto(CircuitSAT,fproblem)
    ans,vals = solvesat(res.circuit; bsconfig, reducer)
    a, b = ProblemReductions.read_solution(fproblem, [vals[res.p]...,vals[res.q]...])
    @show ans
    # @show BRANCHNUMBER
    return a,b
end

function solve_sat(sat::ConstraintSatisfactionProblem)
    res,vals = solvesat(sat)
    return res, Dict(zip(sat.symbols,vals))
end

function solvebip(bip::BooleanInferenceProblem; bsconfig::BranchingStrategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = KNeighborSelector(1,1), measure=NumOfVertices()), reducer=NoReducer())
    bs = initialize_branching_status(bip)
    bs = deduction_reduce(bip,bs,collect(1:length(bip.he2v)))
    ns,res,count_num = branch_and_reduce(bip,bs, bsconfig, reducer)
    @show count_num
    return ns,get_answer(res,bip.literal_num)
end