function contract_region(tn::BipartiteGraph, region::Region, doms::Vector{DomainMask})
    sliced_tensors = Vector{Vector{Tropical{Float64}}}(undef, length(region.tensors))
    tensor_indices = Vector{Vector{Int}}(undef, length(region.tensors))
    
    @inbounds for (i, tensor_id) in enumerate(region.tensors)
        tensor = tn.tensors[tensor_id]
        sliced_tensors[i] = slicing(tensor.tensor, doms, tensor.var_axes)
        tensor_indices[i] = filter(v -> !is_fixed(doms[v]), tensor.var_axes)
    end
    
    # Collect unfixed variables from boundary and inner
    output_vars = filter(v -> !is_fixed(doms[v]), vcat(region.boundary_vars, region.inner_vars))
    contracted = contract_tensors(sliced_tensors, tensor_indices, output_vars)
    
    isempty(output_vars) && @assert length(contracted) == 1
    return contracted, output_vars
end

function contract_tensors(tensors::Vector{Vector{T}}, ixs::Vector{Vector{Int}}, iy::Vector{Int}) where T
    eincode = EinCode(ixs, iy)
    optcode = optimize_code(eincode, uniformsize(eincode, 2), GreedyMethod())
    return optcode([tensor_unwrapping(t) for t in tensors]...)
end

function slicing(tensor::Vector{T}, doms::Vector{DomainMask}, axis_vars::Vector{Int}) where T
    k = trailing_zeros(length(tensor))  # log2(length)
    
    fixed_idx = 0; free_axes = Int[]
    
    @inbounds for axis in 1:k  # each variable
        if is_fixed(doms[axis_vars[axis]])
            has1(doms[axis_vars[axis]]) && (fixed_idx |= (1 << (axis-1)))
        else
            push!(free_axes, axis)
        end
    end
    
    out = Vector{T}(undef, 1 << length(free_axes))
    
    @inbounds for free_idx in eachindex(out)
        full_idx = fixed_idx
        for (i, axis) in enumerate(free_axes)
            ((free_idx-1) >> (i-1)) & 0x1 == 1 && (full_idx |= (1 << (axis-1)))
        end
        out[free_idx] = tensor[full_idx+1]
    end
    
    return out
end


function tensor_unwrapping(vec::Vector{T}) where T
    k = trailing_zeros(length(vec))
    @assert (1 << k) == length(vec) "vector length is not power-of-two"
    dims = ntuple(_->2, k)
    return reshape(vec, dims)
end