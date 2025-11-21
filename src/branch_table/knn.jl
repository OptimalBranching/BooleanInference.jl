function classify_inner_boundary_simple(tn::BipartiteGraph, visited_tensors::BitVector, vars::Vector{Int})
    inner = Int[]
    boundary = Int[]
    @inbounds for vid in vars
        deg_total = tn.vars[vid].deg
        deg_in = 0
        for tensor_id in tn.v2t[vid]
            visited_tensors[tensor_id] && (deg_in += 1)
        end
        if deg_in == deg_total
            push!(inner, vid)
        else
            push!(boundary, vid)
        end
    end
    return inner, boundary
end

function _k_neighboring(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2, hard_only::Bool = false)
    @debug "k_neighboring: focus_var = $focus_var"
    @assert !is_fixed(doms[focus_var]) "Focus variable must be unfixed"

    nvars = length(tn.vars)
    ntensors = length(tn.tensors)

    visited_vars = falses(nvars)
    visited_tensors = falses(ntensors)

    frontier = Int[focus_var]
    collected_vars = Int[focus_var]
    collected_tensors = Int[]

    visited_vars[focus_var] = true

    stopped = false
    @inbounds for _ in 1:k
        isempty(frontier) && break
        next_frontier = Int[]
        for var in frontier
            for tensor_id in tn.v2t[var]
                visited_tensors[tensor_id] && continue
                hard_only && (!is_hard(tn, doms)[tensor_id]; continue)

                visited_tensors[tensor_id] = true
                push!(collected_tensors, tensor_id)

                for var_id in tn.tensors[tensor_id].var_axes
                    if !visited_vars[var_id] && !is_fixed(doms[var_id])
                        visited_vars[var_id] = true
                        push!(collected_vars, var_id)
                        push!(next_frontier, var_id)
                    end
                end

                length(collected_tensors) >= max_tensors && (stopped = true; break;)
            end
            stopped && break
        end
        frontier = next_frontier
        (stopped || isempty(frontier)) && break
    end

    inner, boundary = classify_inner_boundary_simple(tn, visited_tensors, collected_vars)

    sort!(inner)
    sort!(boundary)
    sort!(collected_tensors)
    return Region(focus_var, collected_tensors, inner, boundary)
end

function k_neighboring(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2)
    return _k_neighboring(tn, doms, focus_var; max_tensors = max_tensors, k = k, hard_only = false)
end

function k_neighboring_hard(tn::BipartiteGraph, doms::Vector{DomainMask}, focus_var::Int; max_tensors::Int, k::Int = 2)
    return _k_neighboring(tn, doms, focus_var; max_tensors = max_tensors, k = k, hard_only = true)
end