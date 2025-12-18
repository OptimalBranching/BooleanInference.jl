@inline function compatible(config::UInt16, query_mask0::UInt16, query_mask1::UInt16)
    (config & query_mask0) == 0 && (config & query_mask1) == query_mask1
end

@inline function scan_supports(support::Vector{UInt16}, query_mask0::UInt16, query_mask1::UInt16)
    # the OR of all feasible configs
    valid_or_agg = UInt16(0)
    # the AND of all feasible configs
    valid_and_agg = UInt16(0xFFFF)
    found_any = false

    @inbounds for config in support
        if compatible(config, query_mask0, query_mask1)
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
    # trail_lim[k] stores the trail length when entering level k
    # So to keep levels 0..target_level, we need trail up to trail_lim[target_level+1]
    trail_pos = buffer.trail_lim[target_level + 1]

    # Clear metadata for backtracked assignments
    @inbounds for i in (trail_pos + 1):length(buffer.trail)
        var_id = buffer.trail[i].var_id
        buffer.var_to_level[var_id] = -1  # 重置为未赋值！
        buffer.var_to_reason[var_id].reason_tensor_id = -1 
        buffer.var_to_reason[var_id].mask0 = UInt16(0)
        buffer.var_to_reason[var_id].mask1 = UInt16(0)
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
    fill!(buffer.var_to_reason, PropagateReason(-1, UInt16(0), UInt16(0)))
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
                ctx.buffer.var_to_reason[var_id] = PropagateReason(tensor_id, valid_or, valid_and)
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
    # Initial propagation does not record trail
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
                    buffer.var_to_level[var_id] = current_level
                    buffer.var_to_reason[var_id] = PropagateReason(0, UInt16(0), UInt16(0))  # Direct decision
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
            # @info "Conflict Detected"
            if record_trail
                # @info "[Conflict] $support, $(tensor.var_axes), $(doms[tensor.var_axes])"
                learn_from_failure!(cn, doms, buffer, tensor_id)
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
    if current_level <= 0
        # @info "Conflict at level 0, problem is UNSAT"
        return nothing, 0
    end

    prepare_analysis!(buffer)
    
    conflict_vars = cn.tensors[conflict_tensor_id].var_axes
    # @info "=== Conflict Analysis ==="
    # @info "Conflict tensor: $conflict_tensor_id, vars: $conflict_vars"
    # @info "Current level: $current_level"
    
    # 1. 初始化：从冲突子句开始，当前层变量加入队列
    queue = buffer.conflict_queue
    @inbounds for var_id in conflict_vars
        if is_fixed(doms[var_id]) && buffer.var_to_level[var_id] > 0 && !buffer.seen[var_id]
            buffer.seen[var_id] = true
            push!(buffer.seen_list, var_id)
            if buffer.var_to_level[var_id] == current_level
                push!(queue, var_id)  # 当前层变量加入队列待解析
                # @info "  Queue var $var_id (level $current_level)"
            else
                # 其他层变量直接加入学到的子句
                push!(buffer.current_clause, (var_id, negate_domain(doms[var_id])))
                # @info "  Add to clause: var $var_id at level $(buffer.var_to_level[var_id])"
            end
        elseif buffer.var_to_level[var_id] <= 0
            # @info "  doms[$(var_id)]: $(doms[var_id])"
            # @info "  Skip var $var_id: level = $(buffer.var_to_level[var_id])"
            @assert (buffer.var_to_level[var_id] == 0) || (doms[var_id] == DM_BOTH)
        end
    end
    # @info "Initial queue: $(queue), clause: $(buffer.current_clause)"

    # 2. 解析当前层变量
    while length(queue) > 0
        p = popfirst!(queue)
        # @info "[Resolve] var $p"
        
        reason_id = buffer.var_to_reason[p].reason_tensor_id
        if reason_id != 0  # This var is not a decision variable
            reason_vars = cn.tensors[reason_id].var_axes
            # @info "  Reason: tensor $reason_id with vars $reason_vars"
            
            @inbounds for var_id in reason_vars
                var_level = buffer.var_to_level[var_id]
                if is_fixed(doms[var_id]) && var_level > 0 && !buffer.seen[var_id]
                    buffer.seen[var_id] = true
                    push!(buffer.seen_list, var_id)
                    
                    if var_level == current_level 
                        push!(queue, var_id)
                        # @info "    Queue var $var_id (current level)"
                    else
                        push!(buffer.current_clause, (var_id, negate_domain(doms[var_id])))
                        # @info "    Add to clause: var $var_id at level $var_level"
                    end
                end
            end
        else
            # Decision variable
            push!(buffer.current_clause, (p, negate_domain(doms[p])))
            # @info "  Decision variable, add to clause"
        end
    end
    
    # @info "=== Learned Clause ==="
    # @info "Clause: $(buffer.current_clause)"

    # Update activity scores for all learned literals
    for (var_id, _) in buffer.current_clause
        buffer.activity_scores[var_id] += 1.0
    end

    finish_analysis!(buffer, buffer.current_clause)

    # Store the learned clause (copy it since buffer is reused)
    learned_clause = copy(buffer.current_clause)

    for (var_id, _) in learned_clause
        buffer.activity_scores[var_id] += 1.0
    end

    # Check for duplicates using hash signature
    clause_signature = compute_clause_signature(learned_clause)
    if !(clause_signature in buffer.learned_clauses_signatures)
        push!(buffer.learned_clauses_signatures, clause_signature)
        push!(buffer.learned_clauses, learned_clause)
        # @info "Clause added (total: $(length(buffer.learned_clauses)))"
    # else
        # @info "Clause is duplicate, skipped"
    end
    
    # No backtracking for now
    return learned_clause, 0
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

# ---------------------------------------------------------
# Sub-function 3: Cleanup (no backtracking computation)
# Responsibility: Clear markers only, we don't backtrack for now
# ---------------------------------------------------------
@inline function finish_analysis!(buffer::SolverBuffer, current_clause::Vector{Tuple{Int, DomainMask}})
    # Quickly clear seen markers
    seen = buffer.seen
    for v in buffer.seen_list
        seen[v] = false
    end
    empty!(buffer.seen_list)
    
    # No backtracking for now, just return 0
    return 0
end

# Simple preparation function
@inline function prepare_analysis!(buffer::SolverBuffer)
    # 先清理上一次分析可能残留的 seen 标记
    seen = buffer.seen
    for v in buffer.seen_list
        seen[v] = false
    end
    empty!(buffer.seen_list)
    empty!(buffer.conflict_queue)  # Clear the conflict queue for reuse
    empty!(buffer.current_clause)  # Clear the buffer for building new clause
end