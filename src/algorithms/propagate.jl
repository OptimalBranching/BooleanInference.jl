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
    return propagate(static, doms, all_vars, ws)
end

function propagate(static::TNStatic, doms::Vector{DomainMask}, changed_vars::Vector{Int}, ws::Union{Nothing, DynamicWorkspace}=nothing)
    isempty(changed_vars) && return doms
    working_doms = copy(doms)

    stats = !isnothing(ws) ? ws.branch_stats : nothing
    has_detailed = !isnothing(stats) && !isnothing(stats.detailed)
    has_detailed && record_propagation!(stats)

    # 构建传播队列：仅包含受变化变量影响的 tensor
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

    # 复用传播缓存：避免重复分配 BitVector
    buffers = if !isnothing(ws) && !isnothing(ws.prop_buffers)
        ws.prop_buffers
    else
        buf = PropagationBuffers(static)
        !isnothing(ws) && (ws.prop_buffers = buf)
        buf
    end

    # 计算初始域数量
    initial_domain_count = has_detailed ? sum(count_ones(d.bits & 0x03) for d in doms) : 0

    queue_pos = 1
    iteration_count = 0
    while queue_pos <= length(tensor_queue)
        iteration_count += 1
        tensor_idx = tensor_queue[queue_pos]
        queue_pos += 1
        in_queue[tensor_idx] = false

        tensor = static.tensors[tensor_idx]
        # 直接使用预计算的 masks，无需缓存查找
        masks = static.tensor_to_masks[tensor_idx]

        # Check constraint and propagate
        if !propagate_tensor!(working_doms, tensor, masks, static.v2t,
                              tensor_queue, in_queue, buffers)
            # Contradiction detected
            if has_detailed
                record_early_unsat!(stats)
            end
            return fill(DomainMask(0x00), length(working_doms))
        end
    end

    # 检查是否达到不动点（迭代次数）
    if has_detailed && iteration_count == 1 && queue_pos > length(tensor_queue)
        record_propagation_fixpoint!(stats)
    end

    # 记录域减少数量
    if has_detailed
        final_domain_count = sum(count_ones(d.bits & 0x03) for d in working_doms)
        domain_reduction = initial_domain_count - final_domain_count
        if domain_reduction > 0
            record_domain_reduction!(stats, domain_reduction)
        end
    end

    return working_doms
end

# Propagate constraints from a single tensor. Returns false if contradiction detected.
function propagate_tensor!(working_doms::Vector{DomainMask}, tensor::BoolTensor, masks::TensorMasks, v2t::Vector{Vector{Int}}, tensor_queue::Vector{Int}, in_queue::BitVector, buffers::PropagationBuffers)
    # Step 1: Compute feasible configurations given current domains
    compute_feasible_configs!(buffers.feasible, working_doms, tensor, masks) || return false
    n_feasible = count(buffers.feasible)
    
    # Step 2: Different propagation strategies based on number of feasible configs
    if n_feasible == 1
        # Only one valid config -> fix all variables to that config
        return propagate_unit_constraint!(working_doms, tensor, buffers.feasible, v2t, tensor_queue, in_queue)
    else
        # Multiple configs -> prune unsupported values
        return propagate_support_pruning!(working_doms, tensor, masks, buffers.feasible, buffers.temp, v2t, tensor_queue, in_queue)
    end
end

# Compute which tensor configurations are feasible given current variable domains.
# Returns false if no feasible configuration exists.
@inline function compute_feasible_configs!(feasible::BitVector, working_doms::Vector{DomainMask}, tensor::BoolTensor, masks::TensorMasks)
    n_cfg = length(masks.sat)

    copyto!(feasible, 1, masks.sat, 1, n_cfg)

    n_words = (n_cfg + 63) >> 6
    feas_chunks = feasible.chunks

    # 清空最后一个 UInt64 字中超出 n_cfg 的部分，避免复用大缓冲区时残留位导致误判
    bits_in_last_word = n_cfg & 63  # n_cfg % 64
    if bits_in_last_word != 0
        # 只保留最后字的低 bits_in_last_word 位，清空高位
        mask_val = (UInt64(1) << bits_in_last_word) - 1
        feas_chunks[n_words] &= mask_val
    end

    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        dm_bits = working_doms[var_id].bits

        # 跳过未约束的变量（允许 0 和 1）
        dm_bits == 0x03 && continue
        # 矛盾：变量没有可行值
        dm_bits == 0x00 && return false

        # 选择对应的掩码（0 或 1）
        mask_chunks = dm_bits == 0x01 ? masks.axis_masks0[axis].chunks : masks.axis_masks1[axis].chunks

        # 应用掩码并检查是否还有可行配置
        # 优化：边计算边检查，避免不必要的内存访问
        has_nonzero = false
        for i in 1:n_words
            feas_chunks[i] &= mask_chunks[i]
            has_nonzero |= (feas_chunks[i] != 0)
        end

        # 没有可行配置，提前返回
        has_nonzero || return false
    end

    return true
end

# When tensor has exactly one feasible configuration, fix all its variables to that config.
@inline function propagate_unit_constraint!(working_doms::Vector{DomainMask}, tensor::BoolTensor, feasible::BitVector, v2t::Vector{Vector{Int}}, tensor_queue::Vector{Int}, in_queue::BitVector)
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
@inline function propagate_support_pruning!(working_doms::Vector{DomainMask}, tensor::BoolTensor, masks::TensorMasks, feasible::BitVector, temp::BitVector, v2t::Vector{Vector{Int}}, tensor_queue::Vector{Int}, in_queue::BitVector)
    n_cfg = length(masks.sat)
    n_words = (n_cfg + 63) >> 6
    feas_chunks = feasible.chunks

    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        dm = working_doms[var_id]
        dm_bits = dm.bits

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
                if !update_domain!(working_doms, var_id, dm_bits, DM_1.bits,
                                  v2t, tensor_queue, in_queue)
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
                if !update_domain!(working_doms, var_id, dm_bits, DM_0.bits, v2t, tensor_queue, in_queue)
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



# """
#     LookAheadResult

# Result of look-ahead propagation for a variable assignment.

# Fields:
# - `n_fixed::Int` - Number of additional variables that get fixed
# - `has_conflict::Bool` - Whether a conflict was detected
# - `n_propagations::Int` - Number of propagation steps performed
# """
# struct LookAheadResult
#     n_fixed::Int
#     has_conflict::Bool
#     n_propagations::Int
# end

# """
#     look_ahead_propagation(problem::TNProblem, var_id::Int, value::Bool) -> LookAheadResult

# Perform look-ahead propagation: tentatively assign `var_id` to `value` and propagate
# to see how many additional variables get fixed and whether a conflict occurs.

# This is used to estimate the effectiveness of different branching decisions without
# actually committing to them.
# """
# function look_ahead_propagation(problem::TNProblem, var_id::Int, value::Bool)
#     # Create temporary domain assignment
#     test_doms = get_doms_from_pool!(problem.ws, problem.doms)
#     test_doms[var_id] = value ? DM_1 : DM_0

#     # Count currently fixed variables
#     n_fixed_before = count(is_fixed(dm) for dm in problem.doms)

#     # Propagate
#     propagated = propagate(problem.static, test_doms, problem.ws)

#     # Return domains to pool
#     return_doms_to_pool!(problem.ws, test_doms)

#     # Check for conflict
#     has_conflict = any(dm.bits == 0x00 for dm in propagated)

#     # Count newly fixed variables
#     n_fixed_after = count(is_fixed(dm) for dm in propagated)
#     n_newly_fixed = n_fixed_after - n_fixed_before

#     # Estimate number of propagation steps (active tensors affected by this variable)
#     n_propagations = length(problem.static.v2t[var_id])

#     return LookAheadResult(n_newly_fixed, has_conflict, n_propagations)
# end

# """
#     look_ahead_score(problem::TNProblem, var_id::Int) -> Float64

# Compute a look-ahead score for a variable by testing both possible assignments.
# Higher scores indicate better branching candidates.

# The score considers:
# - How many variables get fixed by each assignment
# - Whether either assignment leads to immediate conflict (pruning)
# - Balance between the two branches
# """
# function look_ahead_score(problem::TNProblem, var_id::Int)
#     result_0 = look_ahead_propagation(problem, var_id, false)
#     result_1 = look_ahead_propagation(problem, var_id, true)

#     # If one branch leads to conflict, that's valuable (immediate pruning)
#     if result_0.has_conflict && result_1.has_conflict
#         # Both lead to conflict - this is UNSAT, but score it very high
#         # so we detect this early
#         return 1e9
#     elseif result_0.has_conflict
#         # Only var=0 conflicts, so var=1 is forced - very valuable
#         return 1e6 + Float64(result_1.n_fixed)
#     elseif result_1.has_conflict
#         # Only var=1 conflicts, so var=0 is forced - very valuable
#         return 1e6 + Float64(result_0.n_fixed)
#     end

#     # Neither leads to conflict - score based on total propagation power
#     # We want variables that cause lots of propagation
#     total_fixed = result_0.n_fixed + result_1.n_fixed

#     # Also consider minimum of the two (we want balanced branches that both make progress)
#     min_fixed = min(result_0.n_fixed, result_1.n_fixed)

#     # Combined score: prefer high total propagation with decent minimum
#     return Float64(total_fixed) + 0.5 * Float64(min_fixed)
# end
