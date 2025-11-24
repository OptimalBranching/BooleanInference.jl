# Solver implementations for CNF SAT

# BooleanInference solver
function solve_instance(::Type{CNFSATProblem}, instance::CNFSATInstance, solver::BooleanInferenceSolver)
    cnf = cnf_instantiation(instance)
    tn_problem = BooleanInference.setup_from_cnf(cnf)
    result = BooleanInference.solve(tn_problem, solver.bsconfig, solver.reducer; show_stats=solver.show_stats)
    return result
end

# Kissat solver - works directly with CNF files
function solve_instance(::Type{CNFSATProblem}, instance::CNFSATInstance, solver::KissatSolver)
    # Kissat can work directly with the CNF file
    result = run_cnf_solver(solver, instance.source_path)
    return result
end

# MiniSat solver - works directly with CNF files
function solve_instance(::Type{CNFSATProblem}, instance::CNFSATInstance, solver::MinisatSolver)
    result = run_cnf_solver(solver, instance.source_path)
    return result
end
