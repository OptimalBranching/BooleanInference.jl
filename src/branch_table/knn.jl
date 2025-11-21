function _classify_inner_boundary(tn::BipartiteGraph, visited_tensors::Set{Int}, vars::Vector{Int})
    inner = Int[]
    boundary = Int[]
    @inbounds for vid in vars
        deg_total = tn.vars[vid].deg
        deg_in = count(tid -> tid ∈ visited_tensors, tn.v2t[vid])
        if deg_in == deg_total
            push!(inner, vid)
        else
            push!(boundary, vid)
        end
    end
    return inner, boundary
end

function _k_neighboring(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2, hard_only::Bool = false)
    @assert !is_fixed(doms[focus_var]) "Focus variable must be unfixed"
    
    visited_vars = Set{Int}(); visited_tensors = Set{Int}()
    collected_vars = Int[]; collected_tensors = Int[]
    
    stack = [(focus_var, k)]
    while !isempty(stack) && length(collected_tensors) < max_tensors
        var_id, depth = pop!(stack)
        depth == 0 && continue
        
        var_id ∉ visited_vars && (push!(visited_vars, var_id); push!(collected_vars, var_id))
        
        for tensor_id in tn.v2t[var_id]
            tensor_id ∈ visited_tensors && continue
            hard_only && !is_hard(tn, doms)[tensor_id] && continue
            
            push!(visited_tensors, tensor_id)
            push!(collected_tensors, tensor_id)
            length(collected_tensors) >= max_tensors && break
            
            for next_var in tn.tensors[tensor_id].var_axes
                next_var ∉ visited_vars && !is_fixed(doms[next_var]) && push!(stack, (next_var, depth - 1))
            end
        end
    end
    
    inner, boundary = _classify_inner_boundary(tn, visited_tensors, collected_vars)
    sort!(inner); sort!(boundary); sort!(collected_tensors)
    return Region(focus_var, collected_tensors, inner, boundary)
end

function k_neighboring(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2)
    return _k_neighboring(tn, doms, focus_var; max_tensors = max_tensors, k = k, hard_only = false)
end

function k_neighboring_hard(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2)
    return _k_neighboring(tn, doms, focus_var; max_tensors = max_tensors, k = k, hard_only = true)
end