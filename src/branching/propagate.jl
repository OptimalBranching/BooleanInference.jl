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
        bit = UInt16(1) << (axis - 1)
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
    trail_pos = target_level == 0 ? 0 : buffer.trail_lim[target_level]

    # Clear metadata for backtracked assignments
    @inbounds for i in (trail_pos + 1):length(buffer.trail)
        var_id = buffer.trail[i].var_id
        buffer.var_to_level[var_id] = -1  # 重置为未赋值！
        buffer.var_to_reason[var_id] = 0
        buffer.seen[var_id] = false       # 保险起见，清理 seen 标记
    end

    # Truncate trail and trail_lim
    resize!(buffer.trail, trail_pos)
    resize!(buffer.trail_lim, target_level)
end

# Clear all decision levels and trail
@inline function clear_trail!(buffer::SolverBuffer)
    # Clear metadata for all variables
    fill!(buffer.var_to_level, -1)
    fill!(buffer.var_to_reason, 0)
    empty!(buffer.trail)
    empty!(buffer.trail_lim)
end

@inline function apply_updates!(doms::Vector{DomainMask}, var_axes::Vector{Int}, valid_or::UInt16, valid_and::UInt16, ctx::PropagationContext, tensor_id::Int)
    @inbounds for (i, var_id) in enumerate(var_axes)
        old_domain = doms[var_id]
        (old_domain == DM_0 || old_domain == DM_1) && continue

        can_be_1 = (valid_or >> (i - 1)) & 1 == 1
        must_be_1 = (valid_and >> (i - 1)) & 1 == 1

        new_dom = must_be_1 ? DM_1 : (can_be_1 ? DM_BOTH : DM_0)

        if new_dom != old_domain
            doms[var_id] = new_dom
            enqueue_neighbors!(ctx.queue, ctx.in_queue, ctx.cn.v2t[var_id])
            
            if ctx.record_trail 
                record_assignment!(ctx.buffer, var_id, new_dom, tensor_id, ctx.level)
                ctx.buffer.var_to_level[var_id] = ctx.level
                ctx.buffer.var_to_reason[var_id] = tensor_id
            end
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
    return propagate_core!(cn, doms, buffer)
end

# probe variable assignments specified by mask and value
# mask: which variables are being set (1 = set, 0 = skip)
# value: the values to set (only meaningful where mask = 1)
# Each variable assignment creates a new decision level
function probe_assignment_core!(cn::ConstraintNetwork, buffer::SolverBuffer, base_doms::Vector{DomainMask}, vars::Vector{Int}, mask::UInt64, value::UInt64, record_trail::Bool, level::Int)
    scratch_doms = buffer.scratch_doms
    copyto!(scratch_doms, base_doms)

    has_any_change = false
    current_level = level

    # Process each variable assignment one by one
    @inbounds for (i, var_id) in enumerate(vars)
        if (mask >> (i - 1)) & 1 == 1
            new_domain = ((value >> (i - 1)) & 1) == 1 ? DM_1 : DM_0
            if scratch_doms[var_id] != new_domain
                # Create a new decision level for this variable
                if record_trail
                    current_level = new_decision_level!(buffer)
                end

                # Set the variable and enqueue affected tensors
                queue = buffer.touched_tensors; empty!(queue)
                in_queue = buffer.in_queue; fill!(in_queue, false)

                scratch_doms[var_id] = new_domain
                if record_trail
                    record_assignment!(buffer, var_id, new_domain, 0, current_level)
                    buffer.var_to_level[var_id] = current_level
                    buffer.var_to_reason[var_id] = 0  # Direct decision
                end

                @inbounds for t_idx in cn.v2t[var_id]
                    if !in_queue[t_idx]
                        in_queue[t_idx] = true
                        push!(queue, t_idx)
                    end
                end

                # Propagate immediately after this assignment
                scratch_doms = propagate_core!(cn, scratch_doms, buffer, record_trail, current_level)

                # Check for contradiction
                if has_contradiction(scratch_doms)
                    return scratch_doms
                end

                has_any_change = true
            end
        end
    end

    return scratch_doms
end

function propagate_core!(cn::ConstraintNetwork, doms::Vector{DomainMask}, buffer::SolverBuffer, record_trail::Bool=false, level::Int=0)
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
            if record_trail
                learn_from_failure!(cn, doms, buffer, tensor_id)
            else
                # Optional: Lightweight activity bump for conflict vars during probing
                # for var_id in tensor.var_axes
                #     buffer.activity_scores[var_id] += 0.5
                # end
            end
            doms[1] = DM_NONE
            return doms
        end

        apply_updates!(doms, tensor.var_axes, valid_or, valid_and, ctx, tensor_id)
    end
    return doms
end

function learn_from_failure!(cn::ConstraintNetwork, doms::Vector{DomainMask}, buffer::SolverBuffer, conflict_tensor_id::Int)
    current_level = get_current_level(buffer)
    # Level 0 冲突意味着无解，返回特殊标记
    current_level <= 0 && return nothing, -1

    prepare_analysis!(buffer)

    # 1. 初始化：标记冲突源 Tensor 中的变量
    conflict_vars = cn.tensors[conflict_tensor_id].var_axes
    path_counter = 0
    p = 0
    
    @inbounds for var_id in conflict_vars
        if !buffer.seen[var_id] && buffer.var_to_level[var_id] > 0
            buffer.seen[var_id] = true
            push!(buffer.seen_list, var_id)
            
            if buffer.var_to_level[var_id] == current_level
                path_counter += 1
            else
                push!(buffer.current_clause, (var_id, negate_domain(doms[var_id])))
            end
        end
    end

    # 2. Trail 回溯主循环：寻找 1-UIP
    trail_idx = length(buffer.trail)
    
    while path_counter > 0
        # 反向查找下一个被标记的变量
        while trail_idx > 0
            assignment = buffer.trail[trail_idx]
            trail_idx -= 1
            p = assignment.var_id
            if buffer.seen[p]
                break
            end
        end

        path_counter -= 1

        if path_counter == 0
            # 找到 1-UIP: p
            # 将其加入子句 (取反)
            push!(buffer.current_clause, (p, negate_domain(doms[p])))
            break
        end

        # 解析变量 p (如果不是决策变量)
        reason_id = buffer.var_to_reason[p]
        if reason_id != 0
            reason_vars = cn.tensors[reason_id].var_axes
            @inbounds for var_id in reason_vars
                if !buffer.seen[var_id] && buffer.var_to_level[var_id] > 0
                    buffer.seen[var_id] = true
                    push!(buffer.seen_list, var_id)
                    
                    if buffer.var_to_level[var_id] == current_level
                        path_counter += 1
                    else
                        push!(buffer.current_clause, (var_id, negate_domain(doms[var_id])))
                    end
                end
            end
        end
    end

    # Update activity scores for all learned literals
    for (var_id, _) in buffer.current_clause
        buffer.activity_scores[var_id] += 1.0
    end

    backtrack_level = finish_analysis!(buffer, buffer.current_clause)

    # Store the learned clause (copy it since buffer is reused)
    learned_clause = copy(buffer.current_clause)

    # Check for duplicates using hash signature (sort first for canonical form)
    clause_signature = compute_clause_signature(learned_clause)
    if !(clause_signature in buffer.learned_clauses_signatures)
        push!(buffer.learned_clauses_signatures, clause_signature)
        push!(buffer.learned_clauses, learned_clause)
    end
    # Note: Always return the clause even if duplicate, caller may need it
    return learned_clause, backtrack_level
end

# ---------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------

# Compute a hash signature for a clause (sorted for canonical form)
# Note: This creates a temporary sorted copy, but it's necessary for canonical hashing
@inline function compute_clause_signature(clause::Vector{Tuple{Int, DomainMask}})::UInt64
    # Sort the clause to get canonical form (same clause content = same signature)
    # This ensures that clauses with same literals in different order have same signature
    return hash(sort(clause))
end

# Trail backtracking - find any marked variable (for multi-level CDCL)
# Responsibility: Find the most recent marked (seen) variable at any level
@inline function find_next_marked_variable(buffer::SolverBuffer, trail_idx::Int)
    trail = buffer.trail
    seen = buffer.seen

    while trail_idx > 0
        assignment = trail[trail_idx]
        trail_idx -= 1

        # Must be marked
        if seen[assignment.var_id]
            return trail_idx, assignment
        end
    end
    return trail_idx, nothing
end

# ---------------------------------------------------------
# Sub-function 3: Cleanup and computation
# Responsibility: Clear markers and compute backtrack level
# ---------------------------------------------------------
@inline function finish_analysis!(buffer::SolverBuffer, current_clause::Vector{Tuple{Int, DomainMask}})
    # 1. Quickly clear seen markers
    seen = buffer.seen
    for v in buffer.seen_list
        seen[v] = false
    end
    empty!(buffer.seen_list)

    # 2. Compute backtrack level
    # In multi-level CDCL: backtrack to the second-highest level in the learned clause
    # This ensures we can still use the learned clause to guide the search
    bt_level = 0
    second_highest = 0

    if !isempty(current_clause)
        var_levels = buffer.var_to_level

        # Find the highest and second-highest levels
        highest = 0
        for (vid, _) in current_clause
            lvl = var_levels[vid]
            if lvl > highest
                second_highest = highest
                highest = lvl
            elseif lvl > second_highest && lvl < highest
                second_highest = lvl
            end
        end

        # Backtrack to second-highest level (or 0 if only one level involved)
        bt_level = second_highest
    end

    return bt_level
end

# Simple preparation function
@inline function prepare_analysis!(buffer::SolverBuffer)
    # 先清理上一次分析可能残留的 seen 标记
    seen = buffer.seen
    for v in buffer.seen_list
        seen[v] = false
    end
    empty!(buffer.seen_list)
    empty!(buffer.current_clause)  # Clear the buffer for building new clause
end