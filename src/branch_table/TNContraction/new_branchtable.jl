struct NewTNContractionSolver <: AbstractTableSolver 
    k::Int
    max_tensors::Int
end
NewTNContractionSolver() = NewTNContractionSolver(1, 2)

function create_region(problem::TNProblem, variable::Int, solver::NewTNContractionSolver)
    # Compute k-neighboring region using current domains. This keeps the implementation simple
    return k_neighboring(problem.static, problem.doms, variable; max_tensors = solver.max_tensors, k = solver.k)
end

function OptimalBranchingCore.branching_table(problem::TNProblem, solver::NewTNContractionSolver, variable::Int)
    stats = problem.ws.branch_stats

    # 1. Build a local region around the branching variable, using current domains
    region = create_region(problem, variable, solver)
    length(region.tensors) == 0 && return BranchingTable(0, [UInt64[]]), Int[]

    var_ids = vcat(region.boundary_vars, region.inner_vars)
    n_vars_total = length(var_ids)

    n_vars_total == 0 && return BranchingTable(0, [UInt64[]]), Int[]

    # 2. Contract the region under the CURRENT domains
    contraction_start_time = time_ns()
    contracted_tensor, output_vars = contract_region(problem.static, region, problem.doms)
    contraction_time = (time_ns() - contraction_start_time) / 1e9
    record_contraction_time!(stats, contraction_time)

    # 3. Use the contraction output axes as our unfixed variable order
    unfixed_var_ids = output_vars
    n_unfixed = length(unfixed_var_ids)
    n_unfixed == 0 && return BranchingTable(0, [UInt64[]]), Int[]

    # 4. Scan the contracted tensor: every entry equal to one(Tropical)
    one_tropical = one(typeof(contracted_tensor[1]))  # TODO: type inference
    configs = Vector{UInt64}()
    nd = ndims(contracted_tensor)
    @inbounds for lin in eachindex(contracted_tensor)
        contracted_tensor[lin] == one_tropical || continue

        linear_idx = LinearIndices(contracted_tensor)[lin] - 1
        config_bits = UInt64(0)
        # LSB encoding (index 1 -> lowest bit)
        for axis in 1:nd
            bit = linear_idx & 0x1
            linear_idx >>= 1
            bit == 1 && (config_bits |= UInt64(1) << (axis - 1))
        end
        push!(configs, config_bits)
    end

    isempty(configs) && return BranchingTable(0, [UInt64[]]), Int[]

    table = BranchingTable(n_unfixed, [ [c] for c in configs ])
    return table, unfixed_var_ids
end