function setup_from_cnf(cnf::CNF)
    return setup_from_sat(Satisfiability(cnf; use_constraints=true))
end

function setup_from_circuit(cir::Circuit)
    return setup_from_sat(CircuitSAT(cir; use_constraints=true))
end

function setup_from_sat(sat::ConstraintSatisfactionProblem)
    static = setup_from_tensor_network(GenericTensorNetwork(sat))
    TNProblem(static)
end
