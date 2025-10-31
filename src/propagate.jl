"""
    TensorMasks

Precomputed bitmasks for efficient propagation:
- `sat`: which configurations satisfy the tensor constraint
- `axis_masks0[i]`: which configurations have variable i = 0
- `axis_masks1[i]`: which configurations have variable i = 1
"""
struct TensorMasks
    sat::BitVector
    axis_masks0::Vector{BitVector}
    axis_masks1::Vector{BitVector}
end

mutable struct PropagationBuffers
    feasible::BitVector
    temp::BitVector
    max_configs::Int
end

function PropagationBuffers(static::TNStatic)
    max_nvars = maximum(length(t.var_axes) for t in static.tensors; init=0)
    max_configs = max_nvars > 0 ? (1 << max_nvars) : 1
    return PropagationBuffers(
        falses(max_configs),
        falses(max_configs),
        max_configs
    )
end


function get_active_tensors(static::TNStatic, doms::Vector{DomainMask})
    active = Int[]
    sizehint!(active, length(static.tensors))  # Pre-allocate to avoid resizing
    @inbounds for (tid, tensor) in enumerate(static.tensors)
        # Check if any variable in this tensor is unfixed
        has_unfixed = false
        for var_id in tensor.var_axes
            dm_bits = doms[var_id].bits
            # Unfixed if domain allows both 0 and 1, or is not yet determined
            if dm_bits == 0x03  # DM_BOTH
                has_unfixed = true
                break  # Early exit: found one unfixed variable
            end
        end
        has_unfixed && push!(active, tid)
    end
    return active
end

function propagate(static::TNStatic, doms::Vector{DomainMask}, ws::Union{Nothing, DynamicWorkspace}=nothing)
    working_doms = copy(doms)
    masks_cache = _masks_cache!(static)

    # Initialize propagation queue with only active tensors (containing unfixed variables)
    tensor_queue = get_active_tensors(static, doms)
    in_queue = falses(length(static.tensors))
    @inbounds for tid in tensor_queue
        in_queue[tid] = true
    end
    queue_pos = 1

    # Use cached buffers from workspace if available, otherwise create new ones
    buffers = if !isnothing(ws) && !isnothing(ws.prop_buffers)
        ws.prop_buffers
    else
        buf = PropagationBuffers(static)
        !isnothing(ws) && (ws.prop_buffers = buf)
        buf
    end

    while queue_pos <= length(tensor_queue)
        tensor_idx = tensor_queue[queue_pos]
        queue_pos += 1
        in_queue[tensor_idx] = false

        tensor = static.tensors[tensor_idx]
        masks = get_mask!(masks_cache, tensor_idx, tensor)

        # Check constraint and propagate
        if !propagate_tensor!(working_doms, tensor, masks, static.v2t,
                              tensor_queue, in_queue, buffers)
            # Contradiction detected
            return fill(DomainMask(0x00), length(working_doms))
        end
    end

    return working_doms
end


# Propagate constraints from a single tensor. Returns false if contradiction detected.
function propagate_tensor!(
    working_doms::Vector{DomainMask},
    tensor::BoolTensor,
    masks::TensorMasks,
    v2t::Vector{Vector{Int}},
    tensor_queue::Vector{Int},
    in_queue::BitVector,
    buffers::PropagationBuffers
)
    # Step 1: Compute feasible configurations given current domains
    if !compute_feasible_configs!(buffers.feasible, working_doms, tensor, masks)
        return false  # No feasible config -> contradiction
    end
    
    n_feasible = count(buffers.feasible)
    
    # Step 2: Different propagation strategies based on number of feasible configs
    if n_feasible == 1
        # Only one valid config -> fix all variables to that config
        return propagate_unit_constraint!(working_doms, tensor, buffers.feasible, v2t, tensor_queue, in_queue)
    else
        # Multiple configs -> prune unsupported values
        return propagate_support_pruning!(working_doms, tensor, masks, 
                                         buffers.feasible, buffers.temp,
                                         v2t, tensor_queue, in_queue)
    end
end


# Compute which tensor configurations are feasible given current variable domains.
# Returns false if no feasible configuration exists.
# Avoids resize by using existing buffer capacity and working with active prefix
@inline function compute_feasible_configs!(feasible::BitVector, working_doms::Vector{DomainMask}, tensor::BoolTensor, masks::TensorMasks)
    n_cfg = length(masks.sat)

    # Work with active prefix instead of resizing
    # Copy only the necessary portion
    @inbounds for i in 1:n_cfg
        feasible[i] = masks.sat[i]
    end

    # Filter by each variable's domain using manual loop to avoid broadcast overhead
    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        dm_bits = working_doms[var_id].bits

        # Skip filtering if domain is unrestricted (both 0 and 1 allowed)
        if dm_bits == 0x03  # DM_BOTH
            continue
        end

        # Directly intersect with the appropriate mask using manual loop
        if dm_bits == 0x01  # DM_0: only 0 allowed
            axis_mask = masks.axis_masks0[axis]
            for i in 1:n_cfg
                feasible[i] = feasible[i] & axis_mask[i]
            end
        elseif dm_bits == 0x02  # DM_1: only 1 allowed
            axis_mask = masks.axis_masks1[axis]
            for i in 1:n_cfg
                feasible[i] = feasible[i] & axis_mask[i]
            end
        else  # dm_bits == 0x00: contradiction
            return false
        end

        # Early exit if no feasible config remains in active prefix
        has_feasible = false
        for i in 1:n_cfg
            if feasible[i]
                has_feasible = true
                break
            end
        end
        has_feasible || return false
    end

    return true
end

# When tensor has exactly one feasible configuration, fix all its variables to that config.
@inline function propagate_unit_constraint!(
    working_doms::Vector{DomainMask},
    tensor::BoolTensor,
    feasible::BitVector,
    v2t::Vector{Vector{Int}},
    tensor_queue::Vector{Int},
    in_queue::BitVector
)
    first_idx = findfirst(feasible)
    config = first_idx - 1
    
    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        bit_val = (config >> (axis - 1)) & 1
        # Branchless: avoid conditional for better performance
        required_bits = ifelse(bit_val == 1, DM_1.bits, DM_0.bits)
        
        old_bits = working_doms[var_id].bits
        new_bits = old_bits & required_bits
        
        # Check for contradiction
        new_bits == 0x00 && return false
        
        # Update domain and enqueue affected tensors
        if new_bits != old_bits
            working_doms[var_id] = DomainMask(new_bits)
            enqueue_affected_tensors!(tensor_queue, in_queue, v2t, var_id)
        end
    end
    
    return true
end

# Prune domain values that have no support in any feasible configuration.
@inline function propagate_support_pruning!(
    working_doms::Vector{DomainMask},
    tensor::BoolTensor,
    masks::TensorMasks,
    feasible::BitVector,
    temp::BitVector,
    v2t::Vector{Vector{Int}},
    tensor_queue::Vector{Int},
    in_queue::BitVector
)
    n_cfg = length(masks.sat)  # Use actual tensor config size, not buffer size

    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        dm = working_doms[var_id]
        dm_bits = dm.bits

        # Check support for value 0 using manual loop to avoid broadcast size mismatch
        if (dm_bits & 0x01) != 0  # has0(dm)
            has_support_0 = false
            axis_mask = masks.axis_masks0[axis]
            for i in 1:n_cfg
                if feasible[i] && axis_mask[i]
                    has_support_0 = true
                    break
                end
            end
            if !has_support_0  # No support for 0
                if !update_domain!(working_doms, var_id, dm_bits, DM_1.bits,
                                  v2t, tensor_queue, in_queue)
                    return false
                end
            end
        end

        # Check support for value 1
        if (dm_bits & 0x02) != 0  # has1(dm)
            has_support_1 = false
            axis_mask = masks.axis_masks1[axis]
            for i in 1:n_cfg
                if feasible[i] && axis_mask[i]
                    has_support_1 = true
                    break
                end
            end
            if !has_support_1  # No support for 1
                if !update_domain!(working_doms, var_id, dm_bits, DM_0.bits,
                                  v2t, tensor_queue, in_queue)
                    return false
                end
            end
        end
    end

    return true
end

# Add all tensors containing the variable to the propagation queue.
@inline function enqueue_affected_tensors!(
    tensor_queue::Vector{Int},
    in_queue::BitVector,
    v2t::Vector{Vector{Int}},
    var_id::Int
)
    @inbounds for tensor_id in v2t[var_id]
        if !in_queue[tensor_id]
            push!(tensor_queue, tensor_id)
            in_queue[tensor_id] = true
        end
    end
end

# Update variable domain by intersecting with keep_mask. Returns false if contradiction.
@inline function update_domain!(
    working_doms::Vector{DomainMask},
    var_id::Int,
    old_bits::UInt8,
    keep_bits::UInt8,
    v2t::Vector{Vector{Int}},
    tensor_queue::Vector{Int},
    in_queue::BitVector
)
    new_bits = old_bits & keep_bits
    
    # Check for contradiction
    new_bits == 0x00 && return false
    
    # Update if changed
    if new_bits != old_bits
        working_doms[var_id] = DomainMask(new_bits)
        enqueue_affected_tensors!(tensor_queue, in_queue, v2t, var_id)
    end
    
    return true
end

# Build support masks for a tensor by enumerating all configurations.
function build_tensor_masks(tensor::BoolTensor)
    nvars = length(tensor.var_axes)
    n_cfg = 1 << nvars

    sat = falses(n_cfg)
    axis_masks0 = [falses(n_cfg) for _ in 1:nvars]
    axis_masks1 = [falses(n_cfg) for _ in 1:nvars]

    @inbounds for cfg in 0:(n_cfg-1)
        # Check if this configuration satisfies the constraint
        if tensor.tensor[cfg+1] == Tropical(0.0)  # one(Tropical{Float64})
            sat[cfg+1] = true
        end

        # Record which value each variable takes in this config
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
    
    # Resize cache if problem structure changed
    if length(vec) != length(static.tensors)
        v = Vector{Union{Nothing, TensorMasks}}(undef, length(static.tensors))
        fill!(v, nothing)
        _MASKS_CACHE[key] = v
        return v
    end
    
    return vec
end
