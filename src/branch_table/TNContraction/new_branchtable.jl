struct NewTNContractionSolver <: AbstractTableSolver 
    k::Int
    max_tensors::Int
end
NewTNContractionSolver() = NewTNContractionSolver(1, 2)

function create_region(problem::TNProblem, variable::Int, solver::NewTNContractionSolver)
    # Compute k-neighboring region using current domains. This keeps the implementation simple
    return k_neighboring(problem.static, problem.doms, variable; max_tensors = solver.max_tensors, k = solver.k)
end

# TODO: change to vector of int for variables
function OptimalBranchingCore.branching_table(problem::TNProblem, solver::NewTNContractionSolver, variable::Int)
    # Build a local region around the branching variable, using current domains
    region = create_region(problem, variable, solver)
    @assert length(region.tensors) > 0 "Panic: region has no tensors"

    var_ids = vcat(region.boundary_vars, region.inner_vars)
    n_vars_total = length(var_ids)

    @assert n_vars_total > 0 "Panic: region has no variables"

    # Contract the region under the CURRENT domains
    contracted_tensor, unfixed_var_ids = contract_region(problem.static, region, problem.doms)

    # Scan the contracted tensor: every entry equal to one(Tropical)
    configs = map(ci -> packint(ci.I .- 1), findall(isone, contracted_tensor))
    # propagate the configurations to get the feasible solutions
    feasible_configs = filter(config -> is_feasible_solution(problem, config), configs)

    table = BranchingTable(length(unfixed_var_ids), [ [c] for c in feasible_configs ])
    return table, unfixed_var_ids
end
packint(indices::NTuple{N, Int}) where {N} = mapreduce(i -> UInt64(1) << (i - 1), |, indices; init = UInt64(0))