function propagate(static::TNStatic, doms::Vector{DomainMask})
    working_doms = copy(doms)
    
    tensor_queue = collect(1:length(static.tensors))
    in_queue = trues(length(static.tensors))
    
    queue_pos = 1  # Current position in queue

    masks_cache = _masks_cache!(static)
    
    while queue_pos <= length(tensor_queue)
        tensor_idx = tensor_queue[queue_pos]
        queue_pos += 1
        in_queue[tensor_idx] = false
        
        tensor = static.tensors[tensor_idx]
        masks = get_mask!(masks_cache, tensor_idx, tensor)
        
        feasible = copy(masks.sat)
        @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
            allowed_axis = falses(length(feasible))
            dm = working_doms[var_id]
            has0(dm) && (allowed_axis .|= masks.axis_masks0[axis])
            has1(dm) && (allowed_axis .|= masks.axis_masks1[axis])
            feasible .&= allowed_axis
            !any(feasible) && return fill(DomainMask(0x00), length(working_doms))
        end

        n_feasible = count(==(true), feasible)
        if n_feasible == 1
            first_idx = findfirst(==(true), feasible)
            first_config = first_idx - 1
            @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
                bit_val = (first_config >> (axis - 1)) & 1
                new_mask = (bit_val == 1) ? DM_1 : DM_0
                
                old_mask = working_doms[var_id]
                new_bits = old_mask.bits & new_mask.bits
                
                if new_bits != old_mask.bits
                    if new_bits == 0x00
                        # Contradiction
                        return fill(DomainMask(0x00), length(working_doms))
                    end
                    working_doms[var_id] = DomainMask(new_bits)
                    
                    for tensor_id in static.v2t[var_id]
                        if !in_queue[tensor_id]
                            push!(tensor_queue, tensor_id)
                            in_queue[tensor_id] = true
                        end
                    end
                end
            end
        else
            @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
                dm = working_doms[var_id]
                if has0(dm)
                    has_support0 = any(feasible .& masks.axis_masks0[axis])
                    if !has_support0
                        new_bits = dm.bits & DM_1.bits
                        if new_bits ==0x00
                            return fill(DomainMask(0x00), length(working_doms))
                        elseif new_bits != dm.bits
                            working_doms[var_id] = DomainMask(new_bits)
                            for tensor_id in static.v2t[var_id]
                                if !in_queue[tensor_id]
                                    push!(tensor_queue, tensor_id)
                                    in_queue[tensor_id] = true
                                end
                            end
                        end
                    end
                end
                if has1(dm)
                    has_support1 = any(feasible .& masks.axis_masks1[axis])
                    if !has_support1
                        new_bits = dm.bits & DM_0.bits
                        if new_bits == 0x00
                            return fill(DomainMask(0x00), length(working_doms))
                        elseif new_bits != dm.bits
                            working_doms[var_id] = DomainMask(new_bits)
                            for tensor_id in static.v2t[var_id]
                                if !in_queue[tensor_id]
                                    push!(tensor_queue, tensor_id)
                                    in_queue[tensor_id] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return working_doms
end

struct TensorMasks
    sat::BitVector
    axis_masks0::Vector{BitVector}
    axis_masks1::Vector{BitVector}
end

function build_tensor_masks(tensor::BoolTensor)
    nvars = length(tensor.var_axes)
    n_cfg = 1 << nvars

    sat = falses(n_cfg)
    axis_masks0 = [falses(n_cfg) for _ in 1:nvars]
    axis_masks1 = [falses(n_cfg) for _ in 1:nvars]

    @inbounds for cfg in 0:(n_cfg-1)
        if tensor.tensor[cfg+1] == Tropical(0.0)  # one(Tropical{Float64})
            sat[cfg+1] = true
        end

        @inbounds for axis in 1:nvars
            bit = (cfg >> (axis - 1)) & 1
            if bit == 0
                axis_masks0[axis][cfg+1] = true
            else
                axis_masks1[axis][cfg+1] = true
            end
        end
    end
    return TensorMasks(sat, axis_masks0, axis_masks1)
end

@inline function get_mask!(cache::Vector{Union{Nothing, TensorMasks}}, idx::Int, tensor::BoolTensor)
    m = cache[idx]
    isnothing(m) && (m = build_tensor_masks(tensor); cache[idx] = m)
    return m
end

const _MASKS_CACHE = IdDict{UInt, Vector{Union{Nothing, TensorMasks}}}()

function _masks_cache!(static::TNStatic)
    key = objectid(static)
    vec = get!(_MASKS_CACHE, key) do
        v = Vector{Union{Nothing, TensorMasks}}(undef, length(static.tensors))
        fill!(v, nothing)
        v
    end
    if length(vec) != length(static.tensors)
        v = Vector{Union{Nothing, TensorMasks}}(undef, length(static.tensors))
        fill!(v, nothing)
        _MASKS_CACHE[key] = v
        return v
    end
    return vec
end