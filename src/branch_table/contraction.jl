function contract_region(tn::ConstraintNetwork, region::Region, doms::Vector{DomainMask})
    sliced_tensors = Vector{Array{Tropical{Float64}}}(undef, length(region.tensors))
    tensor_indices = Vector{Vector{Int}}(undef, length(region.tensors))

    @inbounds for (i, tensor_id) in enumerate(region.tensors)
        tensor = tn.tensors[tensor_id]
        sliced_tensors[i] = slicing(tn, tensor, doms)
        tensor_indices[i] = filter(v -> !is_fixed(doms[v]), tensor.var_axes)
    end

    # Collect unfixed variables from the region
    output_vars = filter(v -> !is_fixed(doms[v]), region.vars)
    contracted = contract_tensors(sliced_tensors, tensor_indices, output_vars)

    isempty(output_vars) && @assert length(contracted) == 1
    return contracted, output_vars
end

function contract_tensors(tensors::Vector{<:AbstractArray{T}}, ixs::Vector{Vector{Int}}, iy::Vector{Int}) where T
    eincode = EinCode(ixs, iy)
    optcode = optimize_code(eincode, uniformsize(eincode, 2), GreedyMethod())
    return optcode(tensors...)
end

# Slice BoolTensor and directly construct multi-dimensional Tropical tensor
function slicing(static::ConstraintNetwork, tensor::BoolTensor, doms::Vector{DomainMask})
    k = length(tensor.var_axes)

    fixed_idx = 0
    free_axes = Int[]

    @inbounds for axis in 1:k
        if is_fixed(doms[tensor.var_axes[axis]])
            has1(doms[tensor.var_axes[axis]]) && (fixed_idx |= (1 << (axis-1)))
        else
            push!(free_axes, axis)
        end
    end

    # Directly construct multi-dimensional array
    n_free = length(free_axes)
    dims = ntuple(_ -> 2, n_free)
    out = Array{Tropical{Float64}}(undef, dims...)

    one_trop = one(Tropical{Float64})
    zero_trop = zero(Tropical{Float64})

    dense_tensor = get_dense_tensor(static, tensor)
    @inbounds for ci in CartesianIndices(dims)
        full_idx = fixed_idx
        for (i, axis) in enumerate(free_axes)
            (ci[i] == 2) && (full_idx |= (1 << (axis-1)))
        end
        out[ci] = dense_tensor[full_idx+1] ? one_trop : zero_trop
    end

    return out
end