# function get_active_tensors(static::TNStatic, doms::Vector{DomainMask})
#     active = Int[]
#     sizehint!(active, length(static.tensors))
#     @inbounds for (tid, tensor) in enumerate(static.tensors)
#         # Check if any variable in this tensor is unfixed
#         has_unfixed = false
#         for var_id in tensor.var_axes
#             dm_bits = doms[var_id].bits
#             # Unfixed if domain allows both 0 and 1, or is not yet determined
#             has_unfixed |= dm_bits == 0x03
#         end
#         has_unfixed && push!(active, tid)
#     end
#     return active
# end

# Backward compatible interface: propagate all tensors when changed_vars not specified
function propagate(static::TNStatic, doms::Vector{DomainMask}, ws::Union{Nothing, DynamicWorkspace}=nothing)
    # When no changed_vars specified, propagate all tensors
    all_vars = collect(1:length(doms))
    trail = !isnothing(ws) ? ws.trail : nothing
    level = !isnothing(trail) ? (isempty(trail.level_start) ? 0 : length(trail.level_start)) : 0
    return propagate(static, doms, all_vars, ws, trail, level)
end

function propagate(static::TNStatic, doms::Vector{DomainMask}, changed_vars::Vector{Int}, ws::Union{Nothing, DynamicWorkspace}=nothing, trail::Union{Nothing, Trail}=nothing, level::Int=0)
    isempty(changed_vars) && return doms
    working_doms = copy(doms)

    stats = !isnothing(ws) ? ws.branch_stats : nothing
    has_detailed = !isnothing(stats) && !isnothing(stats.detailed)
    
    # Record propagation time (nanosecond precision)
    propagation_start_time = has_detailed ? time_ns() : 0

    # Build the propagation queue with tensors affected by the changed variables
    tensor_queue = Int[]
    in_queue = falses(length(static.tensors))
    @inbounds for var_id in changed_vars
        @inbounds for tid in static.v2t[var_id]
            if !in_queue[tid]
                push!(tensor_queue, tid)
                in_queue[tid] = true
            end
        end
    end

    # Reuse propagation buffers to avoid reallocating BitVectors
    buffers = if !isnothing(ws) && !isnothing(ws.prop_buffers)
        ws.prop_buffers
    else
        buf = PropagationBuffers(static)
        !isnothing(ws) && (ws.prop_buffers = buf)
        buf
    end

    # Count initial domain assignments
    initial_domain_count = has_detailed ? sum(count_ones(bits(d) & 0x03) for d in doms) : 0

    queue_pos = 1
    iteration_count = 0
    while queue_pos <= length(tensor_queue)
        iteration_count += 1
        tensor_idx = tensor_queue[queue_pos]
        queue_pos += 1
        in_queue[tensor_idx] = false

        tensor = static.tensors[tensor_idx]
        # Use the precomputed masks directly without cache lookups
        masks = static.tensor_to_masks[tensor_idx]

        # Check constraint and propagate
        if !propagate_tensor!(working_doms, tensor, masks, static.v2t,
                              tensor_queue, in_queue, buffers, trail, level, tensor_idx)
            # Contradiction detected
            has_detailed && record_early_unsat!(stats)
            return fill(DM_NONE, length(working_doms))
        end
    end

    # Record domain reduction counts and elapsed time
    if has_detailed
        propagation_time = (time_ns() - propagation_start_time) / 1e9  # Convert to seconds
        record_propagation!(stats, propagation_time)
        
        final_domain_count = sum(count_ones(bits(d) & 0x03) for d in working_doms)
        domain_reduction = initial_domain_count - final_domain_count
        if domain_reduction > 0
            record_domain_reduction!(stats, domain_reduction)
        end
    end

    return working_doms
end

# Propagate constraints from a single tensor. Returns false if contradiction detected.
function propagate_tensor!(working_doms::Vector{DomainMask}, tensor::BoolTensor, masks::TensorMasks, v2t::Vector{Vector{Int}}, tensor_queue::Vector{Int}, in_queue::BitVector, buffers::PropagationBuffers, trail::Union{Nothing, Trail}, level::Int, tensor_idx::Int)
    # Step 1: Compute feasible configurations given current domains
    compute_feasible_configs!(buffers.feasible, working_doms, tensor, masks) || return false
    n_feasible = count(buffers.feasible)
    
    # Step 2: Different propagation strategies based on number of feasible configs
    if n_feasible == 1
        # Only one valid config -> fix all variables to that config
        return propagate_unit_constraint!(working_doms, tensor, buffers.feasible, v2t, tensor_queue, in_queue, trail, level, tensor_idx)
    else
        # Multiple configs -> prune unsupported values
        return propagate_support_pruning!(working_doms, tensor, masks, buffers.feasible, buffers.temp, v2t, tensor_queue, in_queue, trail, level, tensor_idx)
    end
end

# Compute which tensor configurations are feasible given current variable domains.
# Returns false if no feasible configuration exists.
@inline function compute_feasible_configs!(feasible::BitVector, working_doms::Vector{DomainMask}, tensor::BoolTensor, masks::TensorMasks)
    n_cfg = length(masks.sat)

    copyto!(feasible, 1, masks.sat, 1, n_cfg)

    n_words = (n_cfg + 63) >> 6
    feas_chunks = feasible.chunks

    # Clear stale bits beyond n_cfg in the final UInt64 to avoid reuse artefacts
    bits_in_last_word = n_cfg & 63  # n_cfg % 64
    if bits_in_last_word != 0
        # Keep only the lowest bits_in_last_word bits in the last word
        mask_val = (UInt64(1) << bits_in_last_word) - 1
        feas_chunks[n_words] &= mask_val
    end

    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        dm = working_doms[var_id]
        dm_bits = bits(dm)

        # Skip unconstrained variables (both 0 and 1 are allowed)
        dm == DM_BOTH && continue
        # Contradiction: variable has no feasible assignment
        dm == DM_NONE && return false

        # Pick the corresponding mask (0 or 1)
        mask_chunks = dm == DM_0 ? masks.axis_masks0[axis].chunks : masks.axis_masks1[axis].chunks

        # Apply the mask and ensure a feasible configuration remains
        # Optimization: merge computation and checking to avoid extra memory traffic
        has_nonzero = false
        for i in 1:n_words
            feas_chunks[i] &= mask_chunks[i]
            has_nonzero |= (feas_chunks[i] != 0)
        end

        # No feasible configuration left, exit early
        has_nonzero || return false
    end

    return true
end

# When tensor has exactly one feasible configuration, fix all its variables to that config.
@inline function propagate_unit_constraint!(working_doms::Vector{DomainMask}, tensor::BoolTensor, feasible::BitVector, v2t::Vector{Vector{Int}}, tensor_queue::Vector{Int}, in_queue::BitVector, trail::Union{Nothing, Trail}, level::Int, reason::Int)
    first_idx = findfirst(feasible)
    config = first_idx - 1

    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        bit_val = (config >> (axis - 1)) & 1
        # Branchless: avoid conditional for better performance
        required_bits = ifelse(bit_val == 1, bits(DM_1), bits(DM_0))

        old_bits = bits(working_doms[var_id])
        new_bits = old_bits & required_bits

        # Check for contradiction
        new_bits == 0x00 && return false

        # Update domain and enqueue affected tensors
        if new_bits != old_bits
            working_doms[var_id] = DomainMask(new_bits)
            enqueue_affected_tensors!(tensor_queue, in_queue, v2t, var_id)

            # Record assignment to trail if variable becomes fixed
            if !isnothing(trail) && new_bits != bits(DM_BOTH)
                value = new_bits == bits(DM_1)
                assign_var!(trail, var_id, value, level, reason)
            end
        end
    end
    return true
end

# Prune domain values that have no support in any feasible configuration.
@inline function propagate_support_pruning!(working_doms::Vector{DomainMask}, tensor::BoolTensor, masks::TensorMasks, feasible::BitVector, temp::BitVector, v2t::Vector{Vector{Int}}, tensor_queue::Vector{Int}, in_queue::BitVector, trail::Union{Nothing, Trail}, level::Int, reason::Int)
    n_cfg = length(masks.sat)
    n_words = (n_cfg + 63) >> 6
    feas_chunks = feasible.chunks

    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        dm = working_doms[var_id]
        dm_bits = bits(dm)

        if (dm_bits & 0x01) != 0
            has_support_0 = false
            mask_chunks = masks.axis_masks0[axis].chunks
            for i in 1:n_words
                if (feas_chunks[i] & mask_chunks[i]) != 0
                    has_support_0 = true
                    break
                end
            end
            if !has_support_0
                if !update_domain!(working_doms, var_id, dm_bits, bits(DM_1),
                                  v2t, tensor_queue, in_queue, trail, level, reason)
                    return false
                end
            end
        end

        if (dm_bits & 0x02) != 0
            has_support_1 = false
            mask_chunks = masks.axis_masks1[axis].chunks
            for i in 1:n_words
                if (feas_chunks[i] & mask_chunks[i]) != 0
                    has_support_1 = true
                    break
                end
            end
            if !has_support_1
                if !update_domain!(working_doms, var_id, dm_bits, bits(DM_0), v2t, tensor_queue, in_queue, trail, level, reason)
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
    in_queue::BitVector,
    trail::Union{Nothing, Trail},
    level::Int,
    reason::Int
)
    new_bits = old_bits & keep_bits

    # Check for contradiction
    new_bits == 0x00 && return false

    # Update if changed
    if new_bits != old_bits
        working_doms[var_id] = DomainMask(new_bits)
        enqueue_affected_tensors!(tensor_queue, in_queue, v2t, var_id)

        # Record assignment to trail if variable becomes fixed
        if !isnothing(trail) && new_bits != bits(DM_BOTH)
            value = new_bits == bits(DM_1)
            assign_var!(trail, var_id, value, level, reason)
        end
    end

    return true
end
