function scan_supports(support::Vector{UInt16}, query_mask0::UInt16, query_mask1::UInt16)
    m = query_mask0 | query_mask1  
    # General case: filter by compatibility
    valid_or_agg = UInt16(0)
    valid_and_agg = UInt16(0xFFFF)
    found_any = false

    @inbounds for i in eachindex(support)
        config = support[i]
        if (config & m) == query_mask1
            valid_or_agg |= config
            valid_and_agg &= config
            found_any = true
            # Early exit once both aggregates are saturated.
            if valid_or_agg == 0xFFFF && valid_and_agg == 0x0000
                break
            end
        end
    end
    return valid_or_agg, valid_and_agg, found_any
end

# return (query_mask0, query_mask1)
function compute_query_masks(doms::Vector{DomainMask}, var_axes::Vector{Int})
    @assert length(var_axes) <= 16
    mask0 = UInt16(0); mask1 = UInt16(0);

    @inbounds for i in 1:length(var_axes)
        var_id = var_axes[i]
        domain = doms[var_id]
        bit = UInt16(1) << (i - 1)
        mask0 |= (domain == DM_0) ? bit : UInt16(0)
        mask1 |= (domain == DM_1) ? bit : UInt16(0)
    end
    return mask0, mask1
end

# context for propagation to reduce function parameters
struct PropagationContext
    cn::ConstraintNetwork
    buffer::SolverBuffer
    queue::Vector{Int}
    in_queue::BitVector
    record_trail::Bool
    level::Int
end

@inline function record_assignment!(buffer::SolverBuffer, var_id::Int, new_dom::DomainMask, tensor_id::Int, level::Int)
    push!(buffer.trail, Assignment(var_id, new_dom, tensor_id, level))
end

# Decision level management (level is tracked externally, passed as parameter)
@inline get_current_level(buffer::SolverBuffer) = length(buffer.trail_lim)

# Enter a new decision level
@inline function new_decision_level!(buffer::SolverBuffer)
    push!(buffer.trail_lim, length(buffer.trail))
    return length(buffer.trail_lim)  # Return new level
end

# Backtrack to a specific decision level
@inline function backtrack!(buffer::SolverBuffer, target_level::Int)
    target_level < 0 && error("Invalid backtrack level: $target_level")
    current = length(buffer.trail_lim)
    target_level >= current && return  # Nothing to backtrack

    # Find trail position for target level
    # trail_lim[k] stores the trail length when entering level k
    # So to keep levels 0..target_level, we need trail up to trail_lim[target_level+1]
    trail_pos = buffer.trail_lim[target_level + 1]

    # Truncate trail and trail_lim
    resize!(buffer.trail, trail_pos)
    resize!(buffer.trail_lim, target_level)
end

# Clear all decision levels and trail
@inline function clear_trail!(buffer::SolverBuffer)
    # Clear metadata for all variables
    empty!(buffer.trail)
    empty!(buffer.trail_lim)
end

@inline function apply_updates!(doms::Vector{DomainMask}, var_axes::Vector{Int}, valid_or::UInt16, valid_and::UInt16, ctx::PropagationContext, tensor_id::Int)
    @inbounds for i in 1:length(var_axes)
        var_id = var_axes[i]
        old_domain = doms[var_id]
        (old_domain == DM_0 || old_domain == DM_1) && continue

        bit = UInt16(1) << (i - 1)
        can_be_1  = (valid_or & bit) != UInt16(0)
        must_be_1 = (valid_and & bit) != UInt16(0)

        new_dom = must_be_1 ? DM_1 : (can_be_1 ? DM_BOTH : DM_0)

        if new_dom != old_domain
            doms[var_id] = new_dom
            enqueue_neighbors!(ctx.queue, ctx.in_queue, ctx.cn.v2t[var_id])
            
            if ctx.record_trail 
                record_assignment!(ctx.buffer, var_id, new_dom, tensor_id, ctx.level)
            end
        end
    end
end

@inline function enqueue_neighbors!(queue, in_queue, neighbors)
    @inbounds for t_idx in neighbors
        if !in_queue[t_idx]
            in_queue[t_idx] = true
            push!(queue, t_idx)
        end
    end
end

# Only used for initial propagation
function propagate(cn::ConstraintNetwork, doms::Vector{DomainMask}, initial_touched::Vector{Int}, buffer::SolverBuffer)
    isempty(initial_touched) && return doms
    queue = buffer.touched_tensors; empty!(queue)
    in_queue = buffer.in_queue; fill!(in_queue, false)

    for t_idx in initial_touched
        if !in_queue[t_idx]
            in_queue[t_idx] = true
            push!(queue, t_idx)
        end
    end
    return propagate_core!(cn, doms, buffer, true, 0)
end

# probe variable assignments specified by mask and value
# mask: which variables are being set (1 = set, 0 = skip)
# value: the values to set (only meaningful where mask = 1)
function probe_assignment_core!(cn::ConstraintNetwork, buffer::SolverBuffer, base_doms::Vector{DomainMask}, vars::Vector{Int}, mask::UInt64, value::UInt64, record_trail::Bool, current_level::Int)
    scratch_doms = buffer.scratch_doms
    copyto!(scratch_doms, base_doms)

    # Initialize propagation queue
    queue = buffer.touched_tensors; empty!(queue)
    in_queue = buffer.in_queue; fill!(in_queue, false)

    # println("==========")

    # First, apply all direct assignments at the same decision level
    @inbounds for (i, var_id) in enumerate(vars)
        if (mask >> (i - 1)) & 1 == 1
            new_domain = ((value >> (i - 1)) & 1) == 1 ? DM_1 : DM_0
            if scratch_doms[var_id] != new_domain
                # Set the variable
                scratch_doms[var_id] = new_domain
                # @info "New assignment: v$(var_id) -> $(new_domain) "
                
                if record_trail
                    record_assignment!(buffer, var_id, new_domain, 0, current_level)
                end

                # Enqueue affected tensors for propagation
                @inbounds for t_idx in cn.v2t[var_id]
                    if !in_queue[t_idx]
                        in_queue[t_idx] = true
                        push!(queue, t_idx)
                    end
                end
            end
        end
    end

    # Then propagate all changes together
    scratch_doms = propagate_core!(cn, scratch_doms, buffer, record_trail, current_level)
    return scratch_doms
end

function propagate_core!(cn::ConstraintNetwork, doms::Vector{DomainMask}, buffer::SolverBuffer, record_trail::Bool, level::Int)
    queue = buffer.touched_tensors
    in_queue = buffer.in_queue
    ctx = PropagationContext(cn, buffer, queue, in_queue, record_trail, level)
    
    queue_head = 1
    while queue_head <= length(queue)
        tensor_id = queue[queue_head]
        queue_head += 1
        in_queue[tensor_id] = false

        tensor = cn.tensors[tensor_id]
        q_mask0, q_mask1 = compute_query_masks(doms, tensor.var_axes)

        support = get_support(cn, tensor)
        valid_or, valid_and, found = scan_supports(support, q_mask0, q_mask1)
        if !found
            doms[1] = DM_NONE
            return doms
        end

        apply_updates!(doms, tensor.var_axes, valid_or, valid_and, ctx, tensor_id)
    end
    return doms
end
