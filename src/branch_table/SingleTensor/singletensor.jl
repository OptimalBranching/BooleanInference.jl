# Single Tensor Branching Table Solver
# This solver generates a branching table by considering only a single tensor at a time
# instead of contracting a region of multiple tensors.

struct SingleTensorSolver <: AbstractTableSolver end

function partition_tensor_variables(tensor_vars::Vector{Int}, doms::Vector{DomainMask})
    fixed_positions = Tuple{Int, Bool}[]
    unfixed_positions = Int[]
    unfixed_var_ids = Int[]

    @inbounds for (i, var_id) in enumerate(tensor_vars)
        if is_fixed(doms[var_id])
            # Variable is fixed
            value = has1(doms[var_id])  # true if fixed to 1, false if fixed to 0
            push!(fixed_positions, (i, value))
        else
            # Variable is unfixed
            push!(unfixed_positions, i)
            push!(unfixed_var_ids, var_id)
        end
    end

    return fixed_positions, unfixed_positions, unfixed_var_ids
end


function enumerate_tensor_configs(
    tensor::BoolTensor,
    fixed_positions::Vector{Tuple{Int, Bool}},
    unfixed_positions::Vector{Int}
)
    nvars = length(tensor.var_axes)

    # Build fixed mask and pattern
    fixed_mask = UInt64(0)
    fixed_pattern = UInt64(0)
    @inbounds for (pos, val) in fixed_positions
        bit_mask = UInt64(1) << (pos - 1)
        fixed_mask |= bit_mask
        if val
            fixed_pattern |= bit_mask
        end
    end

    # Enumerate all configurations
    valid_configs = UInt64[]
    one_tropical = one(Tropical{Float64})

    @inbounds for config in 0:(2^nvars - 1)
        # Check if fixed variables match
        if (config & fixed_mask) != fixed_pattern
            continue
        end

        # Check if this configuration satisfies the tensor constraint
        if tensor.tensor[config + 1] == one_tropical
            # Extract only unfixed variable bits
            unfixed_config = UInt64(0)
            for (new_pos, old_pos) in enumerate(unfixed_positions)
                bit = (config >> (old_pos - 1)) & 0x1
                unfixed_config |= bit << (new_pos - 1)
            end
            push!(valid_configs, unfixed_config)
        end
    end

    return valid_configs
end

function OptimalBranchingCore.branching_table(problem::TNProblem, ::SingleTensorSolver, tensor_id::Int)
    # Get the tensor
    tensor = problem.static.tensors[tensor_id]
    tensor_vars = tensor.var_axes

    # Partition variables into fixed and unfixed
    fixed_positions, unfixed_positions, unfixed_var_ids =
        partition_tensor_variables(tensor_vars, problem.doms)

    n_unfixed = length(unfixed_var_ids)

    @debug "SingleTensorSolver: tensor=$tensor_id, n_vars=$(length(tensor_vars)), n_unfixed=$n_unfixed"

    # If all variables are fixed, check if assignment is valid
    if n_unfixed == 0
        # Build the full configuration from fixed variables
        config = UInt64(0)
        @inbounds for (pos, val) in fixed_positions
            if val
                config |= UInt64(1) << (pos - 1)
            end
        end

        # Check if valid
        one_tropical = one(Tropical{Float64})
        if tensor.tensor[config + 1] == one_tropical
            # Valid but no unfixed variables
            return BranchingTable(0, [UInt64[]]), Int[]
        else
            # Invalid - UNSAT
            return BranchingTable(0, Vector{UInt64}[]), Int[]
        end
    end

    # Enumerate valid configurations
    valid_configs = enumerate_tensor_configs(tensor, fixed_positions, unfixed_positions)

    @debug "Found $(length(valid_configs)) valid configurations for tensor $tensor_id"

    # If no valid configurations, return empty table (UNSAT)
    if isempty(valid_configs)
        return BranchingTable(0, Vector{UInt64}[]), Int[]
    end

    # Each valid configuration becomes its own group
    # This allows the branching algorithm to choose between different variable assignments
    config_groups = [[config] for config in valid_configs]
    table = BranchingTable(n_unfixed, config_groups)

    return table, unfixed_var_ids
end
