function scan_supports(support::Vector{UInt16}, support_or::UInt16, support_and::UInt16, query_mask0::UInt16, query_mask1::UInt16)
    m = query_mask0 | query_mask1
    # General case: filter by compatibility
    if m == UInt16(0)
        return support_or, support_and, !isempty(support)
    end
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
            if valid_or_agg == UInt16(0xFFFF) && valid_and_agg == UInt16(0x0000)
                break
            end
        end
    end
    return valid_or_agg, valid_and_agg, found_any
end

# return (query_mask0, query_mask1)
function compute_query_masks(doms::Vector{DomainMask}, var_axes::Vector{Int})
    @assert length(var_axes) <= 16
    mask0 = UInt16(0)
    mask1 = UInt16(0)

    @inbounds for i in eachindex(var_axes)
        var_id = var_axes[i]
        domain = doms[var_id]
        bit = UInt16(1) << (i - 1)
        if domain == DM_0
            mask0 |= bit
        elseif domain == DM_1
            mask1 |= bit
        end
    end
    return mask0, mask1
end

# context for propagation to reduce function parameters
struct PropagationContext
    cn::ConstraintNetwork
    queue::Vector{Int}
    in_queue::BitVector
end

@inline function apply_updates!(doms::Vector{DomainMask}, var_axes::Vector{Int}, valid_or::UInt16, valid_and::UInt16, ctx::PropagationContext)
    @inbounds for i in 1:length(var_axes)
        var_id = var_axes[i]
        old_domain = doms[var_id]
        (old_domain == DM_0 || old_domain == DM_1) && continue

        bit = UInt16(1) << (i - 1)
        can_be_1 = (valid_or & bit) != UInt16(0)
        must_be_1 = (valid_and & bit) != UInt16(0)

        new_dom = must_be_1 ? DM_1 : (can_be_1 ? DM_BOTH : DM_0)

        if new_dom != old_domain
            doms[var_id] = new_dom
            enqueue_neighbors!(ctx.queue, ctx.in_queue, ctx.cn.v2t[var_id])
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

# probe variable assignments specified by mask and value
# mask: which variables are being set (1 = set, 0 = skip)
# value: the values to set (only meaningful where mask = 1)
function probe_assignment_core!(problem::TNProblem, buffer::SolverBuffer, base_doms::Vector{DomainMask}, vars::Vector{Int}, mask::UInt64, value::UInt64)
    scratch_doms = buffer.scratch_doms
    copyto!(scratch_doms, base_doms)

    # Initialize propagation queue
    queue = buffer.touched_tensors
    empty!(queue)
    in_queue = buffer.in_queue
    fill!(in_queue, false)

    # First, apply all direct assignments at the same decision level
    @inbounds for (i, var_id) in enumerate(vars)
        if (mask >> (i - 1)) & 1 == 1
            new_domain = ((value >> (i - 1)) & 1) == 1 ? DM_1 : DM_0
            if scratch_doms[var_id] != new_domain
                # Set the variable
                scratch_doms[var_id] = new_domain

                # Enqueue affected tensors for propagation
                @inbounds for t_idx in problem.static.v2t[var_id]
                    if !in_queue[t_idx]
                        in_queue[t_idx] = true
                        push!(queue, t_idx)
                    end
                end
            end
        end
    end

    # Then propagate all changes together
    scratch_doms = propagate_core!(problem.static, scratch_doms, buffer)
    return scratch_doms
end

"""
    apply_assignment_inplace!(problem, buffer, doms, vars, mask, value) -> Bool

Apply assignment directly to `doms` in-place and propagate.
Returns true if successful, false if contradiction found.

Use this when you know the assignment won't cause contradictions
(e.g., during γ=1 reduction phase) to avoid copying overhead.
"""
function apply_assignment_inplace!(problem::TNProblem, buffer::SolverBuffer, doms::Vector{DomainMask}, vars::Vector{Int}, mask::UInt64, value::UInt64)
    # Initialize propagation queue
    queue = buffer.touched_tensors
    empty!(queue)
    in_queue = buffer.in_queue
    fill!(in_queue, false)

    # Apply direct assignments
    @inbounds for (i, var_id) in enumerate(vars)
        if (mask >> (i - 1)) & 1 == 1
            new_domain = ((value >> (i - 1)) & 1) == 1 ? DM_1 : DM_0
            if doms[var_id] != new_domain
                doms[var_id] = new_domain
                @inbounds for t_idx in problem.static.v2t[var_id]
                    if !in_queue[t_idx]
                        in_queue[t_idx] = true
                        push!(queue, t_idx)
                    end
                end
            end
        end
    end

    # Propagate in-place
    propagate_core!(problem.static, doms, buffer)
    return doms[1] != DM_NONE
end

function propagate_core!(cn::ConstraintNetwork, doms::Vector{DomainMask}, buffer::SolverBuffer)
    queue = buffer.touched_tensors
    in_queue = buffer.in_queue
    ctx = PropagationContext(cn, queue, in_queue)

    queue_head = 1
    while queue_head <= length(queue)
        tensor_id = queue[queue_head]
        queue_head += 1
        in_queue[tensor_id] = false

        tensor = cn.tensors[tensor_id]
        q_mask0, q_mask1 = compute_query_masks(doms, tensor.var_axes)

        support = get_support(cn, tensor)
        support_or = get_support_or(cn, tensor)
        support_and = get_support_and(cn, tensor)
        valid_or, valid_and, found = scan_supports(support, support_or, support_and, q_mask0, q_mask1)
        if !found
            doms[1] = DM_NONE
            return doms
        end

        apply_updates!(doms, tensor.var_axes, valid_or, valid_and, ctx)
    end
    return doms
end

"""
    propagate!(problem::TNProblem)

Simple in-place propagation on a TNProblem.
Propagates constraints until fixpoint, modifying problem.doms in-place.
Returns true if consistent, false if contradiction found.
"""
function propagate!(problem::TNProblem)
    cn = problem.static
    doms = problem.doms
    buffer = problem.buffer

    # Initialize queue with all tensors (full propagation)
    queue = buffer.touched_tensors
    empty!(queue)
    in_queue = buffer.in_queue
    fill!(in_queue, false)

    for t_idx in eachindex(cn.tensors)
        in_queue[t_idx] = true
        push!(queue, t_idx)
    end

    result = propagate_core!(cn, doms, buffer)
    return result[1] != DM_NONE
end
