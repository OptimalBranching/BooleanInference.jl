# Main propagate function: returns (new_doms, propagated_vars)
function propagate(static::BipartiteGraph, doms::Vector{DomainMask}, touched_tensors::Vector{Int})
    isempty(touched_tensors) && return doms, Int[]
    working_doms = copy(doms); propagated_vars = Int[]

    # Track tensors currently enqueued; once processed they can be re-enqueued
    in_queue = falses(length(static.tensors))
    @inbounds for t in touched_tensors
        in_queue[t] = true
    end

    queue_index = 1
    while queue_index <= length(touched_tensors)
        tensor_id = touched_tensors[queue_index]
        queue_index += 1
        in_queue[tensor_id] = false

        tensor = static.tensors[tensor_id]
        feasible_configs = find_feasible_configs(working_doms, tensor)
        isempty(feasible_configs) && (working_doms[1]=DM_NONE; return working_doms, propagated_vars)

        updated_vars = update_domains_from_configs!(working_doms, tensor, feasible_configs)
        append!(propagated_vars, updated_vars)

        @inbounds for v in updated_vars
            for t in static.v2t[v]
                if !in_queue[t]
                    in_queue[t] = true
                    push!(touched_tensors, t)
                end
            end
        end
    end
    return working_doms, propagated_vars
end

# Find all configurations of the tensor that are feasible given current variable domains
function find_feasible_configs(doms::Vector{DomainMask}, tensor::BoolTensor)
    num_configs = 1 << length(tensor.var_axes)
    feasible = Int[]

    # For each variable: compute which bit value (0 or 1) is allowed
    must_be_one_mask = 0  # Variables that must be 1
    must_be_zero_mask = 0  # Variables that must be 0

    @inbounds for (axis, var_id) in enumerate(tensor.var_axes)
        domain = doms[var_id]
        if domain == DM_1
            must_be_one_mask |= (1 << (axis - 1))
        elseif domain == DM_0
            must_be_zero_mask |= (1 << (axis - 1))
        elseif domain == DM_NONE
            # No feasible configs
            return feasible
        end
    end

    @inbounds for config in 0:(num_configs-1)
        (config & must_be_zero_mask) == 0 || continue
        (config & must_be_one_mask) == must_be_one_mask || continue

        tensor.tensor[config + 1] == one(Tropical{Float64}) && push!(feasible, config)
    end

    return feasible
end

# Update variable domains based on feasible configurations
function update_domains_from_configs!(doms::Vector{DomainMask}, tensor::BoolTensor, feasible_configs::Vector{Int})
    updated_vars = Int[]

    for (axis, var_id) in enumerate(tensor.var_axes)
        current_domain = doms[var_id]
        (current_domain == DM_0 || current_domain == DM_1) && continue

        bit_values = [(config >> (axis - 1)) & 1 for config in feasible_configs]
        has_zero, has_one = (0 ∈ bit_values), (1 ∈ bit_values)

        new_domain = has_zero && has_one ? DM_BOTH : has_zero ? DM_0 : has_one ? DM_1 : DM_NONE

        if new_domain != current_domain
            doms[var_id] = new_domain
            push!(updated_vars, var_id)
        end
    end

    return updated_vars
end
