# Local workspace for k-neighboring algorithm
mutable struct KNNWorkspace
    epoch::Int
    visited_vars::Vector{Int}
    visited_tensors::Vector{Int}
    frontier::Vector{Int}
    next_frontier::Vector{Int}
    collected_vars::Vector{Int}
    collected_tensors::Vector{Int}
end

function KNNWorkspace(var_num::Int, tensor_num::Int)
    return KNNWorkspace(
        1,
        zeros(Int, var_num),
        zeros(Int, tensor_num),
        Int[],
        Int[],
        Int[],
        Int[]
    )
end

@inline function _mark_var!(ws::KNNWorkspace, var::Int)
    ws.visited_vars[var] = ws.epoch
end
@inline function _mark_tensor!(ws::KNNWorkspace, tensor::Int)
    ws.visited_tensors[tensor] = ws.epoch
end
@inline function _check_seen_var(ws::KNNWorkspace, var::Int)
    return ws.visited_vars[var] == ws.epoch
end
@inline function _check_seen_tensor(ws::KNNWorkspace, tensor::Int)
    return ws.visited_tensors[tensor] == ws.epoch
end

@inline function _bump_epoch!(ws::KNNWorkspace)
    ws.epoch += 1
end

function expand_one_var!(
    tn::BipartiteGraph,
    ws::KNNWorkspace,
    doms::Vector{DomainMask},
    max_tensors::Int
)::Bool  # returns `true` if STOPPED EARLY due to limits; `false` otherwise
    empty!(ws.next_frontier)
    @inbounds for var in ws.frontier
        for tensor_id in tn.v2t[var]
            if !_check_seen_tensor(ws, tensor_id)
                _mark_tensor!(ws, tensor_id)
                push!(ws.collected_tensors, tensor_id)
                if length(ws.collected_tensors) >= max_tensors
                    return true
                end
            end
            for e in tn.t2v[tensor_id]
                var_id = e.var
                # Only expand to unfixed variables
                if !_check_seen_var(ws, var_id) 
                    _mark_var!(ws, var_id)
                    push!(ws.collected_vars, var_id)
                    push!(ws.next_frontier, var_id)
                end
            end
        end
    end
    return false
end

function classify_inner_boundary!(tn::BipartiteGraph, ws::KNNWorkspace, vars::Vector{Int})
    inner = Int[]
    boundary = Int[]
    @inbounds for vid in vars
        deg_total = tn.vars[vid].deg
        deg_in = 0
        for tensor_id in tn.v2t[vid]
            _check_seen_tensor(ws, tensor_id) && (deg_in += 1)
        end
        if deg_in == deg_total
            push!(inner, vid)
        else
            push!(boundary, vid)
        end
    end
    return inner, boundary
end


function k_neighboring(
    tn::BipartiteGraph,
    doms::Vector{DomainMask},
    focus_var::Int;
    max_tensors::Int,
    k::Int = 2,
)
    @debug "k_neighboring: focus_var = $focus_var"
    @assert k ≥ 0
    @assert !is_fixed(doms[focus_var]) "Focus variable must be unfixed"
    
    # Create local workspace for this call
    ws = KNNWorkspace(length(tn.vars), length(tn.tensors))
    
    # Initialize with focus variable
    _mark_var!(ws, focus_var)
    push!(ws.frontier, focus_var)
    push!(ws.collected_vars, focus_var)

    # k var-hops (only expanding to unfixed variables)
    stopped = false
    @inbounds for _ in 1:k
        stopped = expand_one_var!(tn, ws, doms, max_tensors)
        ws.frontier, ws.next_frontier = ws.next_frontier, ws.frontier
        empty!(ws.next_frontier)
        (stopped || isempty(ws.frontier)) && break
    end

    # classify inner/boundary using current epoch marks for tensor-membership
    inner, boundary = classify_inner_boundary!(tn, ws, ws.collected_vars)

    # deterministic ordering
    sort!(inner); sort!(boundary); sort!(ws.collected_tensors)
    return Region(focus_var, ws.collected_tensors, inner, boundary)
end