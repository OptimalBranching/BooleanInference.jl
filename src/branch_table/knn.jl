function _k_neighboring(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2, hard_only::Bool = false)
    @assert !is_fixed(doms[focus_var]) "Focus variable must be unfixed"

    visited_vars = Set{Int}()
    visited_tensors = Set{Int}()
    collected_vars = Int[focus_var]
    collected_tensors = Int[]
    
    push!(visited_vars, focus_var)
    
    # Use BFS with two separate queues for variables and tensors
    var_queue = [focus_var]
    
    for hop in 1:k
        # Step 1: From current variables to tensors
        tensor_queue = Int[]
        for var_id in var_queue
            for tensor_id in tn.v2t[var_id]
                if tensor_id ∉ visited_tensors
                    if hard_only && !is_hard(tn, doms)[tensor_id]
                        continue
                    end
                    push!(visited_tensors, tensor_id)
                    push!(collected_tensors, tensor_id)
                    push!(tensor_queue, tensor_id)
                    if length(collected_tensors) >= max_tensors
                        break
                    end
                end
            end
            if length(collected_tensors) >= max_tensors
                break
            end
        end
        
        # Step 2: From current tensors to next layer variables
        # Always collect variables from the tensors we got, even if max_tensors is reached
        var_queue = Int[]
        for tensor_id in tensor_queue
            for next_var in tn.tensors[tensor_id].var_axes
                if next_var ∉ visited_vars && !is_fixed(doms[next_var])
                    push!(visited_vars, next_var)
                    push!(collected_vars, next_var)
                    push!(var_queue, next_var)
                end
            end
        end
        
        # Stop after collecting variables if max_tensors is reached
        if length(collected_tensors) >= max_tensors
            break
        end
    end

    sort!(collected_vars)
    sort!(collected_tensors)
    return Region(focus_var, collected_tensors, collected_vars)
end

function k_neighboring(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2)
    return _k_neighboring(tn, doms, focus_var; max_tensors = max_tensors, k = k, hard_only = false)
end

function k_neighboring_hard(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2)
    return _k_neighboring(tn, doms, focus_var; max_tensors = max_tensors, k = k, hard_only = true)
end