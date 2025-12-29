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
    buffer::SolverBuffer
    queue::Vector{Int}
    in_queue::BitVector
    clause_queue::Vector{Int}
    clause_in_queue::BitVector
    learned_clauses::Vector{ClauseTensor}
    v2c::Vector{Vector{Int}}
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
            !isempty(ctx.learned_clauses) && enqueue_clause_neighbors!(ctx.clause_queue, ctx.clause_in_queue, ctx.v2c[var_id])

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

# ClauseTensor neighbors use a separate queue.
@inline function enqueue_clause_neighbors!(queue, in_queue, neighbors)
    @inbounds for c_idx in neighbors
        if !in_queue[c_idx]
            in_queue[c_idx] = true
            push!(queue, c_idx)
        end
    end
end

@inline function ensure_clause_queue!(buffer::SolverBuffer, n_clauses::Int)
    if length(buffer.clause_in_queue) != n_clauses
        resize!(buffer.clause_in_queue, n_clauses)
    end
    fill!(buffer.clause_in_queue, false)
end

@inline function is_literal_true(dm::DomainMask, polarity::Bool)::Bool
    return polarity ? (dm == DM_1) : (dm == DM_0)
end

@inline function is_literal_false(dm::DomainMask, polarity::Bool)::Bool
    return polarity ? (dm == DM_0) : (dm == DM_1)
end

# O(k) propagation for ClauseTensor
@inline function propagate_clause!(doms::Vector{DomainMask}, clause::ClauseTensor, ctx::PropagationContext)
    unassigned_count = 0
    unassigned_idx = 0
    pol = clause.polarity

    @inbounds for i in 1:length(clause.vars)
        var_id = clause.vars[i]
        dm = doms[var_id]

        if is_literal_true(dm, pol[i])
            return doms
        elseif is_literal_false(dm, pol[i])
            continue
        else
            unassigned_count += 1
            unassigned_idx = i
        end
    end

    if unassigned_count == 0
        doms[1] = DM_NONE
        return doms
    elseif unassigned_count == 1
        var_id = clause.vars[unassigned_idx]
        new_dom = pol[unassigned_idx] ? DM_1 : DM_0
        doms[var_id] = new_dom
        # @show var_id, new_dom
        enqueue_neighbors!(ctx.queue, ctx.in_queue, ctx.cn.v2t[var_id])
        !isempty(ctx.learned_clauses) && enqueue_clause_neighbors!(ctx.clause_queue, ctx.clause_in_queue, ctx.v2c[var_id])
    end
    return doms
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
    return propagate_core!(cn, ClauseTensor[], Vector{Vector{Int}}(), doms, buffer)
end

function propagate(cn::ConstraintNetwork, clauses::Vector{ClauseTensor}, v2c::Vector{Vector{Int}}, doms::Vector{DomainMask}, initial_touched_tensors::Vector{Int}, initial_touched_clauses::Vector{Int}, buffer::SolverBuffer)
    queue = buffer.touched_tensors
    empty!(queue)
    in_queue = buffer.in_queue
    fill!(in_queue, false)
    clause_queue = buffer.touched_clauses
    empty!(clause_queue)
    ensure_clause_queue!(buffer, length(clauses))
    clause_in_queue = buffer.clause_in_queue

    @inbounds for t_idx in initial_touched_tensors
        if !in_queue[t_idx]
            in_queue[t_idx] = true
            push!(queue, t_idx)
        end
    end
    @inbounds for c_idx in initial_touched_clauses
        if !clause_in_queue[c_idx]
            clause_in_queue[c_idx] = true
            push!(clause_queue, c_idx)
        end
    end
    return propagate_core!(cn, clauses, v2c, doms, buffer)
end

# probe variable assignments specified by mask and value
# mask: which variables are being set (1 = set, 0 = skip)
# value: the values to set (only meaningful where mask = 1)
function probe_assignment_core!(problem::TNProblem, buffer::SolverBuffer, base_doms::Vector{DomainMask}, vars::Vector{Int}, mask::UInt64, value::UInt64)
    clauses = problem.learned_clauses
    scratch_doms = buffer.scratch_doms
    copyto!(scratch_doms, base_doms)

    # Initialize propagation queue
    queue = buffer.touched_tensors
    empty!(queue)
    in_queue = buffer.in_queue
    fill!(in_queue, false)
    clause_queue = buffer.touched_clauses
    empty!(clause_queue)
    ensure_clause_queue!(buffer, length(clauses))
    clause_in_queue = buffer.clause_in_queue

    # println("==========")

    # First, apply all direct assignments at the same decision level
    @inbounds for (i, var_id) in enumerate(vars)
        if (mask >> (i - 1)) & 1 == 1
            new_domain = ((value >> (i - 1)) & 1) == 1 ? DM_1 : DM_0
            if scratch_doms[var_id] != new_domain
                # Set the variable
                scratch_doms[var_id] = new_domain
                # @info "New assignment: v$(var_id) -> $(new_domain) "

                # Enqueue affected tensors for propagation
                @inbounds for t_idx in problem.static.v2t[var_id]
                    if !in_queue[t_idx]
                        in_queue[t_idx] = true
                        push!(queue, t_idx)
                    end
                end

                # Enqueue affected learned clauses for propagation
                if !isempty(clauses)
                    @inbounds for c_idx in problem.v2c[var_id]
                        if !clause_in_queue[c_idx]
                            clause_in_queue[c_idx] = true
                            push!(clause_queue, c_idx)
                        end
                    end
                end
            end
        end
    end

    # Then propagate all changes together
    scratch_doms = propagate_core!(problem.static, clauses, problem.v2c, scratch_doms, buffer)
    return scratch_doms
end

function propagate_core!(cn::ConstraintNetwork, clauses::Vector{ClauseTensor}, v2c::Vector{Vector{Int}}, doms::Vector{DomainMask}, buffer::SolverBuffer)
    queue = buffer.touched_tensors
    in_queue = buffer.in_queue
    clause_queue = buffer.touched_clauses
    clause_in_queue = buffer.clause_in_queue
    ctx = PropagationContext(cn, buffer, queue, in_queue, clause_queue, clause_in_queue, clauses, v2c)

    queue_head = 1
    clause_head = 1
    while queue_head <= length(queue) || clause_head <= length(clause_queue)
        if queue_head <= length(queue)
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
        else
            clause_id = clause_queue[clause_head]
            clause_head += 1
            clause_in_queue[clause_id] = false

            clause = clauses[clause_id]
            propagate_clause!(doms, clause, ctx)
            doms[1] == DM_NONE && return doms
        end
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

    # Propagate without learned clauses
    result = propagate_core!(cn, ClauseTensor[], Vector{Vector{Int}}(), doms, buffer)
    return result[1] != DM_NONE
end
