function contract_region(tn::TNStatic, region::Region, doms::Vector{DomainMask})
    n_tensors = length(region.tensors)
    
    sliced_tensors = Vector{Vector{Tropical{Float64}}}(undef, n_tensors)
    tensor_indices = Vector{Vector{Int}}(undef, n_tensors)
    
    @inbounds for (i, tensor_id) in enumerate(region.tensors)
        # Get original tensor and its variable axes
        original_tensor = tn.tensors[tensor_id]
        var_axes = original_tensor.var_axes
        tensor_data = original_tensor.tensor
        
        # Slice tensor according to fixed variables
        sliced = slicing(tensor_data, doms, var_axes)
        sliced_tensors[i] = sliced
        
        # Determine remaining (unfixed) variable indices
        # After slicing, only unfixed variables remain as indices
        remaining_vars = Int[]
        for var_id in var_axes
            if !is_fixed(doms[var_id])
                push!(remaining_vars, var_id)
            end
        end
        tensor_indices[i] = remaining_vars
    end
    
    # Output: only unfixed variables in the region
    # (fixed variables have already been sliced out)
    output_vars = Int[]
    
    # Collect unfixed variables
    for var_id in region.boundary_vars
        if !is_fixed(doms[var_id])
            push!(output_vars, var_id)
        end
    end
    for var_id in region.inner_vars
        if !is_fixed(doms[var_id])
            push!(output_vars, var_id)
        end
    end
    
    # Special case: if all variables are fixed, output is scalar
    if isempty(output_vars)
        # Contract everything to a scalar
        # Use empty output indices
        contracted = contract_tensors(sliced_tensors, tensor_indices, Int[])
        @assert length(contracted) == 1
        return contracted, Int[]
    else
        contracted = contract_tensors(sliced_tensors, tensor_indices, output_vars)
        return contracted, output_vars
    end
end

function contract_tensors(tensors::Vector{Vector{T}}, ixs::Vector{Vector{Int}}, iy::Vector{Int}) where T
    eincode = EinCode(ixs, iy)
    optcode = optimize_code(eincode, uniformsize(eincode, 2), GreedyMethod())    
    unwrapped_tensors = [tensor_unwrapping(t) for t in tensors]
    result = optcode(unwrapped_tensors...)
    return result
end


function slicing(tensor::Vector{T}, doms::Vector{DomainMask}, axis_vars::Vector{Int}) where T
    # Number of axes (Boolean => size 2 per axis)
    k = trailing_zeros(length(tensor)) # log2
    fixed_axes = Int[]; fixed_vals = Int[]; free_axes = Int[]
    
    for axis in 1:k  # each variable
        var_id = axis_vars[axis]
        dom_mask = doms[var_id]
        if is_fixed(dom_mask)
            push!(fixed_axes, axis)
            push!(fixed_vals, has1(dom_mask) ? 1 : 0)
        else
            push!(free_axes, axis)
        end
    end
    
    n_free = length(free_axes)
    out_len = 1 << n_free # 2^n_free
    out = Vector{T}(undef, out_len)
    
    # Iterate over all assignments to free variables
    @inbounds for free_idx in 0:(out_len-1)
        # Build full index
        full_idx = 0
        
        # Set free variable bits
        for (i, axis) in enumerate(free_axes)
            bit = (free_idx >> (i-1)) & 0x1  # get the i-th bit of free_idx
            full_idx |= (bit << (axis-1))  # set free-idx in the full_idx
        end
        
        # Set fixed variable bits
        for (axis, val) in zip(fixed_axes, fixed_vals)
            full_idx |= (val << (axis-1))
        end
        
        out[free_idx+1] = tensor[full_idx+1]
    end
    
    return out
end


function tensor_unwrapping(vec::Vector{T}) where T
    len = length(vec)
    @assert len > 0
    k = trailing_zeros(len)
    @assert (1 << k) == len "vector length is not power-of-two"
    dims = ntuple(_->2, k)
    return reshape(vec, dims)
end