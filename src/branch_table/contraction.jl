function create_region(cn::ConstraintNetwork, doms::Vector{DomainMask}, variable::Int, selector::AbstractSelector)
    max_tensors = hasfield(typeof(selector), :max_tensors) ? selector.max_tensors : 20
    k = hasfield(typeof(selector), :k) ? selector.k : 3
    return k_neighboring(cn, doms, variable; max_tensors=max_tensors, k=k)
end

function contract_region(tn::ConstraintNetwork, region::Region, doms::Vector{DomainMask})
    # Collect sliced tensors, handling fully-fixed tensors specially
    active_tensors = Array{Bool}[]
    active_indices = Vector{Int}[]

    @inbounds for tensor_id in region.tensors
        tensor = tn.tensors[tensor_id]
        sliced = slicing(tn, tensor, doms)
        unfixed_vars = filter(v -> !is_fixed(doms[v]), tensor.var_axes)

        if isempty(unfixed_vars)
            # All variables are fixed - this is a scalar (0-dim array)
            # If the scalar is false, the entire contraction is infeasible
            if !only(sliced)
                # Return empty result - no feasible configurations
                output_vars = filter(v -> !is_fixed(doms[v]), region.vars)
                dims = ntuple(_ -> 2, length(output_vars))
                return fill(false, dims), output_vars
            end
            # If true, skip this tensor (it contributes factor of 1)
        else
            push!(active_tensors, sliced)
            push!(active_indices, unfixed_vars)
        end
    end

    # Collect unfixed variables from the region
    output_vars = filter(v -> !is_fixed(doms[v]), region.vars)

    # If no active tensors remain, all were true scalars - result is all true
    if isempty(active_tensors)
        dims = ntuple(_ -> 2, length(output_vars))
        return fill(true, dims), output_vars
    end

    contracted = contract_tensors(active_tensors, active_indices, output_vars)

    isempty(output_vars) && @assert length(contracted) == 1
    return contracted, output_vars
end

function contract_tensors(tensors::Vector{<:AbstractArray{Bool}}, ixs::Vector{Vector{Int}}, iy::Vector{Int})
    # Convert Bool arrays to Int for contraction (OMEinsum works with standard arithmetic)
    int_tensors = [Int.(t) for t in tensors]

    eincode = EinCode(ixs, iy)
    optcode = optimize_code(eincode, uniformsize(eincode, 2), GreedyMethod())

    # Contract using standard arithmetic, then convert back to Bool
    result = optcode(int_tensors...)
    return result .> 0
end

# Slice BoolTensor and directly construct multi-dimensional Bool tensor
function slicing(static::ConstraintNetwork, tensor::BoolTensor, doms::Vector{DomainMask})
    free_axes = Int[]

    @inbounds for (i, var_id) in enumerate(tensor.var_axes)
        dm = doms[var_id]
        is_fixed(dm) || push!(free_axes, i)
    end
    fixed_mask, fixed_val = mask_value(doms, tensor.var_axes, UInt16)

    dims = ntuple(_ -> 2, length(free_axes))
    out = fill(false, dims)  # Allocate dense array

    supports = get_support(static, tensor)

    @inbounds for config in supports
        if (config & fixed_mask) == fixed_val
            dense_idx = 1
            for (bit_pos, axis_idx) in enumerate(free_axes)
                if (config >> (axis_idx - 1)) & 1 == 1
                    dense_idx += (1 << (bit_pos - 1))
                end
            end
            out[dense_idx] = true
        end
    end
    return out
end