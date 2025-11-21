# Backward compatible interface: propagate all tensors when changed_vars not specified
function propagate(static::BipartiteGraph, doms::Vector{DomainMask})
    return propagate(static, doms, collect(1:length(doms)), nothing)
end

function propagate(static::BipartiteGraph, doms::Vector{DomainMask}, changed_vars::Vector{Int}, propagated_vars::Union{Nothing, Vector{Int}}=nothing)
    isempty(changed_vars) && return doms

    working_doms = copy(doms)
    tensor_queue = unique(vcat([static.v2t[v] for v in changed_vars]...))
    queue_index = 1

    while queue_index <= length(tensor_queue)
        tensor_id = tensor_queue[queue_index]
        queue_index += 1

        tensor = static.tensors[tensor_id]
        feasible_configs = find_feasible_configs(working_doms, tensor)

        isempty(feasible_configs) && return fill(DM_NONE, length(working_doms))

        updated_vars = update_domains_from_configs!(working_doms, tensor, feasible_configs)
        !isnothing(propagated_vars) && append!(propagated_vars, updated_vars)

        new_tensors = unique(vcat([static.v2t[v] for v in updated_vars]...))
        append!(tensor_queue, filter(t -> t ∉ tensor_queue[queue_index:end], new_tensors))
    end

    return working_doms
end

# Find all configurations of the tensor that are feasible given current variable domains
function find_feasible_configs(doms::Vector{DomainMask}, tensor::BoolTensor)
    num_configs = 1 << length(tensor.var_axes)

    is_config_feasible(config) = begin
        # Check if this configuration satisfies the tensor constraint
        tensor.tensor[config + 1] != Tropical(0.0) && return false
        
        # Check if configuration is compatible with current variable domains
        all(enumerate(tensor.var_axes)) do (axis, var_id)
            bit_value = (config >> (axis - 1)) & 1
            domain = doms[var_id]
            (bit_value == 0 && domain ∉ (DM_1, DM_NONE)) || (bit_value == 1 && domain ∉ (DM_0, DM_NONE))
        end
    end

    return filter(is_config_feasible, 0:(num_configs-1))
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
