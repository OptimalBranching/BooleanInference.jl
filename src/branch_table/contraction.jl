function create_region(cn::ConstraintNetwork, doms::Vector{DomainMask}, variable::Int, selector::AbstractSelector)
    return k_neighboring(cn, doms, variable; max_tensors = selector.max_tensors, k = selector.k)
end

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

const ONE_TROP = one(Tropical{Float64})
const ZERO_TROP = zero(Tropical{Float64})

# Slice BoolTensor and directly construct multi-dimensional Tropical tensor
function slicing(static::ConstraintNetwork, tensor::BoolTensor, doms::Vector{DomainMask})
    free_axes = Int[]
    
    @inbounds for (i, var_id) in enumerate(tensor.var_axes)
        dm = doms[var_id]
        is_fixed(dm) || push!(free_axes, i)
    end
    fixed_mask, fixed_val = mask_value(doms, tensor.var_axes, UInt32)

    dims = ntuple(_ -> 2, length(free_axes))
    out = fill(ZERO_TROP, dims) # Allocate dense array
    
    supports = get_support(static, tensor)

    @inbounds for config in supports
        if (config & fixed_mask) == fixed_val
            dense_idx = 1
            for (bit_pos, axis_idx) in enumerate(free_axes)
                if (config >> (axis_idx - 1)) & 1 == 1
                    dense_idx += (1 << (bit_pos - 1))
                end
            end
            out[dense_idx] = ONE_TROP
        end
    end
    return out
end