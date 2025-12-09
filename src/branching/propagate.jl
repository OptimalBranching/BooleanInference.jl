@inline function scan_supports(support::Vector{UInt16}, query_mask0::UInt16, query_mask1::UInt16)
    # the OR of all feasible configs
    valid_or_agg = UInt16(0)
    # the AND of all feasible configs
    valid_and_agg = UInt16(0xFFFF)
    found_any = false

    @inbounds for config in support
        if (config & query_mask0) == 0 && (config & query_mask1) == query_mask1
            valid_or_agg |= config
            valid_and_agg &= config
            found_any = true
        end
    end
    return valid_or_agg, valid_and_agg, found_any
end

# return (query_mask0, query_mask1)
@inline function compute_query_masks(doms::Vector{DomainMask}, var_axes::Vector{Int})
    mask0 = UInt16(0); mask1 = UInt16(0);

    @inbounds for (axis, var_id) in enumerate(var_axes)
        domain = doms[var_id]
        if domain == DM_0
            mask0 |= (UInt16(1) << (axis - 1))
        elseif domain == DM_1
            mask1 |= (UInt16(1) << (axis - 1))
        end
        @assert domain != DM_NONE
    end
    return mask0, mask1
end

@inline function apply_updates!(doms::Vector{DomainMask}, var_axes::Vector{Int}, valid_or::UInt16, valid_and::UInt16, cn::ConstraintNetwork, queue::Vector{Int}, inqueue::BitVector)
    @inbounds for (i, var_id) in enumerate(var_axes)
        old_domain = doms[var_id]
        (old_domain == DM_0 || old_domain == DM_1) && continue

        can_be_1 = (valid_or >> (i - 1)) & 1 == 1
        must_be_1 = (valid_and >> (i - 1)) & 1 == 1

        new_dom = if must_be_1
            DM_1
        elseif !can_be_1
            DM_0
        else
            DM_BOTH
        end

        if new_dom != old_domain
            doms[var_id] = new_dom
            enqueue_neighbors!(queue, inqueue, cn.v2t[var_id])
        end
    end
end

@inline function enqueue_neighbors!(queue, in_queue, neighbors)
    for t_idx in neighbors
        if !in_queue[t_idx]
            in_queue[t_idx] = true
            push!(queue, t_idx)
        end
    end
end

# Main propagate function: returns new_doms
function propagate(cn::ConstraintNetwork, doms::Vector{DomainMask}, initial_touched::Vector{Int}, buffer::SolverBuffer)
    isempty(initial_touched) && return doms

    queue = buffer.touched_tensors
    empty!(queue)

    in_queue = buffer.in_queue
    fill!(in_queue, false)

    for t_idx in initial_touched
        if !in_queue[t_idx]
            in_queue[t_idx] = true
            push!(queue, t_idx)
        end
    end

    return propagate_core!(cn, doms, buffer)
end

function propagate_core!(cn::ConstraintNetwork, doms::Vector{DomainMask}, buffer::SolverBuffer)
    queue = buffer.touched_tensors
    in_queue = buffer.in_queue
    queue_head = 1

    while queue_head <= length(queue)
        tensor_id = queue[queue_head]
        queue_head += 1
        in_queue[tensor_id] = false

        tensor = cn.tensors[tensor_id]
        q_mask0, q_mask1 = compute_query_masks(doms, tensor.var_axes)
        # has_conflict && (println("tensor $(tensor_id) has conflict"); doms[1] = DM_NONE; return doms)

        support = get_support(cn, tensor)
        valid_or, valid_and, found = scan_supports(support, q_mask0, q_mask1)
        !found && (doms[1] = DM_NONE; return doms)

        apply_updates!(doms, tensor.var_axes, valid_or, valid_and, cn, queue, in_queue)
    end
    return doms
end

# probe variable assignments specified by mask and value
# mask: which variables are being set (1 = set, 0 = skip)
# value: the values to set (only meaningful where mask = 1)
function probe_assignment_core!(cn::ConstraintNetwork, buffer::SolverBuffer, base_doms::Vector{DomainMask}, vars::Vector{Int}, mask::UInt64, value::UInt64)
    scratch_doms = buffer.scratch_doms
    copyto!(scratch_doms, base_doms)

    queue = buffer.touched_tensors
    empty!(queue)
    in_queue = buffer.in_queue
    fill!(in_queue, false)

    has_change = false
    @inbounds for (i, var_id) in enumerate(vars)
        if (mask >> (i - 1)) & 1 == 1
            new_domain = ((value >> (i - 1)) & 1) == 1 ? DM_1 : DM_0
            if scratch_doms[var_id] != new_domain
                scratch_doms[var_id] = new_domain
                has_change = true

                for t_idx in cn.v2t[var_id]
                    if !in_queue[t_idx]
                        in_queue[t_idx] = true
                        push!(queue, t_idx)
                    end
                end
            end
        end
    end

    !has_change && return scratch_doms
    propagate_core!(cn, scratch_doms, buffer)
    return scratch_doms
end