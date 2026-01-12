"""
    tn_to_cnf(cn::ConstraintNetwork) -> Vector{Vector{Int}}

Convert a ConstraintNetwork (tensor network) to CNF in DIMACS-style format.
Each tensor becomes a set of clauses encoding its satisfying configurations.

This is useful for:
1. Using CDCL solvers to learn clauses after TN precontraction
2. Hybrid solving strategies
"""
function tn_to_cnf(cn::ConstraintNetwork)
    cnf = Vector{Vector{Int}}()

    for tensor in cn.tensors
        tensor_to_cnf!(cnf, cn, tensor)
    end

    return cnf
end

"""
    tensor_to_cnf!(cnf, cn, tensor)

Add clauses to cnf that encode the satisfying configurations of a single tensor.
Uses the standard encoding: for each unsatisfying configuration, add a clause
that blocks it.
"""
function tensor_to_cnf!(cnf::Vector{Vector{Int}}, cn::ConstraintNetwork, tensor::BoolTensor)
    vars = tensor.var_axes
    n_vars = length(vars)
    td = get_tensor_data(cn, tensor)

    # Handle special cases
    if n_vars == 0
        # Scalar tensor - nothing to encode
        return
    end

    # For small tensors (≤ 5 vars), use direct blocking clauses for unsatisfying configs
    # For larger tensors, could use Tseitin transformation, but for now keep it simple
    n_configs = 1 << n_vars
    dense = td.dense_tensor

    # Count satisfying configs to decide encoding strategy
    n_sat = length(td.support)
    n_unsat = n_configs - n_sat

    if n_sat == 0
        # Unsatisfiable tensor - add empty clause marker
        # In practice this shouldn't happen after precontraction
        @warn "Tensor with no satisfying configurations detected"
        push!(cnf, Int[])  # Empty clause = UNSAT
        return
    end

    if n_sat == n_configs
        # All configs satisfy - no constraint needed
        return
    end

    # Choose encoding based on which is smaller
    if n_unsat <= n_sat
        # Block each unsatisfying configuration
        for config in 0:(n_configs-1)
            dense[config+1] && continue  # Skip satisfying configs

            clause = Int[]
            for (bit_pos, var_id) in enumerate(vars)
                bit_val = (config >> (bit_pos - 1)) & 1
                # If bit is 1, add negative literal; if 0, add positive
                push!(clause, bit_val == 1 ? -var_id : var_id)
            end
            push!(cnf, clause)
        end
    else
        # Use dual encoding: express as OR of satisfying configs
        # This requires auxiliary variables for larger tensors
        if n_vars <= 3
            # For small tensors, blocking clauses are fine even if n_unsat > n_sat
            for config in 0:(n_configs-1)
                dense[config+1] && continue

                clause = Int[]
                for (bit_pos, var_id) in enumerate(vars)
                    bit_val = (config >> (bit_pos - 1)) & 1
                    push!(clause, bit_val == 1 ? -var_id : var_id)
                end
                push!(cnf, clause)
            end
        else
            # For larger tensors with very few unsatisfying configs, 
            # fall back to blocking clauses
            for config in 0:(n_configs-1)
                dense[config+1] && continue

                clause = Int[]
                for (bit_pos, var_id) in enumerate(vars)
                    bit_val = (config >> (bit_pos - 1)) & 1
                    push!(clause, bit_val == 1 ? -var_id : var_id)
                end
                push!(cnf, clause)
            end
        end
    end
end

"""
    num_tn_vars(cn::ConstraintNetwork) -> Int

Return the number of variables in the constraint network.
"""
num_tn_vars(cn::ConstraintNetwork) = length(cn.vars)

"""
    tn_to_cnf_with_doms(cn::ConstraintNetwork, doms::Vector{DomainMask}) -> (cnf, nvars)

Convert active tensors to CNF, incorporating current variable assignments.
Returns CNF clauses and the number of variables.

Only processes tensors that have at least one unfixed variable.
Adds unit clauses for fixed variables.
"""
function tn_to_cnf_with_doms(cn::ConstraintNetwork, doms::Vector{DomainMask})
    nvars = length(cn.vars)
    cnf = Vector{Vector{Int}}()

    # Add unit clauses for fixed variables
    for var_id in 1:nvars
        dm = doms[var_id]
        if dm == DM_0
            push!(cnf, [-var_id])
        elseif dm == DM_1
            push!(cnf, [var_id])
        end
    end

    # Convert only active tensors (those with at least one unfixed var)
    for tensor in cn.tensors
        # Check if tensor has any unfixed variable
        has_unfixed = false
        for var_id in tensor.var_axes
            if !is_fixed(doms[var_id])
                has_unfixed = true
                break
            end
        end
        has_unfixed || continue

        # Convert this tensor to CNF (slicing on fixed vars)
        tensor_to_cnf_sliced!(cnf, cn, tensor, doms)
    end

    return cnf, nvars
end

"""
    tensor_to_cnf_sliced!(cnf, cn, tensor, doms)

Add clauses for a tensor, slicing on fixed variables.
"""
function tensor_to_cnf_sliced!(cnf::Vector{Vector{Int}}, cn::ConstraintNetwork, tensor::BoolTensor, doms::Vector{DomainMask})
    vars = tensor.var_axes
    n_vars = length(vars)
    td = get_tensor_data(cn, tensor)
    dense = td.dense_tensor

    # Find unfixed vars and build slicing mask
    unfixed_vars = Int[]
    unfixed_positions = Int[]
    fixed_mask = UInt64(0)
    fixed_value = UInt64(0)

    for (i, var_id) in enumerate(vars)
        dm = doms[var_id]
        if dm == DM_1
            fixed_mask |= UInt64(1) << (i - 1)
            fixed_value |= UInt64(1) << (i - 1)
        elseif dm == DM_0
            fixed_mask |= UInt64(1) << (i - 1)
        else
            push!(unfixed_vars, var_id)
            push!(unfixed_positions, i)
        end
    end

    isempty(unfixed_vars) && return  # All fixed, skip

    n_unfixed = length(unfixed_vars)
    n_configs = 1 << n_unfixed

    # For each unfixed config, check if it's satisfiable given fixed values
    for unfixed_config in 0:(n_configs-1)
        # Reconstruct full config
        full_config = fixed_value
        for (new_i, old_i) in enumerate(unfixed_positions)
            if ((unfixed_config >> (new_i - 1)) & 1) == 1
                full_config |= UInt64(1) << (old_i - 1)
            end
        end

        # If this config is satisfying, skip
        dense[full_config+1] && continue

        # Block this unsatisfying config
        clause = Int[]
        for (bit_pos, var_id) in enumerate(unfixed_vars)
            bit_val = (unfixed_config >> (bit_pos - 1)) & 1
            push!(clause, bit_val == 1 ? -var_id : var_id)
        end
        push!(cnf, clause)
    end
end
