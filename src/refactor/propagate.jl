"""
    propagate!(static::TNStatic, doms::Vector{DomainMask})

Perform unit propagation on the given domain masks.
Returns updated domain masks after propagation.

This function repeatedly checks each tensor (constraint):
- If only one configuration satisfies the tensor given current domains, fix variables to that configuration
- Continue until no more variables can be fixed (fixpoint)

Based on the deduction_reduce logic from reducer.jl.

Optimizations:
- Only check tensors whose variables have been recently modified
- Early termination when enumerating feasible configs
- Avoid redundant Set operations
"""
function propagate!(static::TNStatic, doms::Vector{DomainMask})
    # Create a working copy to avoid modifying input
    working_doms = copy(doms)
    
    # Queue of tensors to check (initially all)
    # Use a simple vector as FIFO queue
    tensor_queue = Int32[]
    in_queue = falses(length(static.tensors))
    
    # Add all tensors to initial queue
    for i in 1:length(static.tensors)
        push!(tensor_queue, Int32(i))
        in_queue[i] = true
    end
    
    queue_pos = 1  # Current position in queue
    
    while queue_pos <= length(tensor_queue)
        tensor_idx = tensor_queue[queue_pos]
        queue_pos += 1
        in_queue[tensor_idx] = false
        
        tensor = static.tensors[tensor_idx]
        
        # Check how many configurations satisfy this tensor
        # Returns (count, first_config) for efficiency
        n_feasible, first_config = count_feasible_configs(tensor, working_doms)
        
        if n_feasible == 0
            # Contradiction - no feasible configuration
            return fill(DomainMask(0x00), length(working_doms))
        elseif n_feasible == 1
            # Unit propagation: only one way to satisfy this tensor
            # Extract variable assignments and fix them
            for (axis, var_id) in enumerate(tensor.var_axes)
                bit_val = (first_config >> (axis - 1)) & 1
                new_mask = (bit_val == 1) ? DM_1 : DM_0
                
                old_mask = working_doms[var_id.id]
                new_bits = old_mask.bits & new_mask.bits
                
                if new_bits != old_mask.bits
                    if new_bits == 0x00
                        # Contradiction
                        return fill(DomainMask(0x00), length(working_doms))
                    end
                    working_doms[var_id.id] = DomainMask(new_bits)
                    
                    # Add all tensors connected to this variable to queue
                    for tid in static.v2t[var_id.id]
                        if !in_queue[tid.id]
                            push!(tensor_queue, tid.id)
                            in_queue[tid.id] = true
                        end
                    end
                end
            end
        end
        # If n_feasible > 1, multiple feasible configs - can't deduce anything
    end
    
    return working_doms
end

"""
    count_feasible_configs(tensor::BoolTensor, doms::Vector{DomainMask})

Count feasible configurations and return the first one found.
Returns (count, first_config) where:
- count: number of feasible configurations (stops counting at 2 for efficiency)
- first_config: the first feasible 0-based configuration index found

This is optimized for unit propagation:
- If count == 0: contradiction
- If count == 1: can propagate using first_config
- If count >= 2: cannot propagate (stops early)
"""
function count_feasible_configs(tensor::BoolTensor, doms::Vector{DomainMask})
    var_axes = tensor.var_axes
    n_vars = length(var_axes)
    n_configs = 1 << n_vars
    
    count = 0
    first_config = 0
    
    for config in 0:(n_configs-1)
        # Check if this config is allowed by current domains
        allowed = true
        @inbounds for (axis, var_id) in enumerate(var_axes)
            bit_val = (config >> (axis - 1)) & 1
            dm = doms[var_id.id]
            
            # Check if this bit value is in the domain
            if bit_val == 0
                if !has0(dm)
                    allowed = false
                    break
                end
            else  # bit_val == 1
                if !has1(dm)
                    allowed = false
                    break
                end
            end
        end
        
        if !allowed
            continue
        end
        
        # Check if this config satisfies the tensor constraint
        # tensor.tensor is 1-indexed, config is 0-indexed
        @inbounds if tensor.tensor[config + 1] == Tropical(0.0)
            count += 1
            if count == 1
                first_config = config
            elseif count == 2
                # Early termination: we know there are multiple solutions
                # No point continuing
                return (2, first_config)
            end
        end
    end
    
    return (count, first_config)
end

