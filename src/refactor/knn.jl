@inline function _mark_var!(ws::HopWorkspace, var::Int32)
    ws.visited_vars[var] = ws.epoch
end
@inline function _mark_tensor!(ws::HopWorkspace, tensor::Int32)
    ws.visited_tensors[tensor] = ws.epoch
end
@inline function _check_seen_var(ws::HopWorkspace, var::Int32)
    return ws.visited_vars[var] == ws.epoch
end
@inline function _check_seen_tensor(ws::HopWorkspace, tensor::Int32)
    return ws.visited_tensors[tensor] == ws.epoch
end

@inline function _bump_epoch!(ws::HopWorkspace)
    ws.epoch += 1
end

function expand_one_var!(
    tn::TNStatic,
    ws::HopWorkspace,
    max_tensors::Int
)::Bool  # returns `true` if STOPPED EARLY due to limits; `false` otherwise
    empty!(ws.next_frontier)
    @inbounds for var in ws.frontier
        for fid in tn.v2t[var]
            f = fid.id
            if !_check_seen_tensor(ws, f)
                _mark_tensor!(ws, f)
                push!(ws.collected_tensors, f)
                if length(ws.collected_tensors) >= max_tensors
                    return true
                end
            end
            for e in tn.t2v[f]
                u = e.var.id
                if !_check_seen_var(ws, u)
                    _mark_var!(ws, u)
                    push!(ws.collected_vars, u)
                    push!(ws.next_frontier, u)
                end
            end
        end
    end
    return false
end

function classify_inner_boundary!(tn::TNStatic, ws::HopWorkspace, vars::Vector{Int32})
    inner = Int32[]
    boundary = Int32[]
    @inbounds for vid in vars
        deg_total = tn.vars[vid].deg
        deg_in = 0
        for fid in tn.v2t[vid]
            _check_seen_tensor(ws, fid.id) && (deg_in += 1)
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
    tn::TNStatic,
    ws::HopWorkspace,
    focus_var::Int32;
    max_tensors::Int,
    k::Int = 2,
)
    @assert k ≥ 0
    # bump epoch & reset buffers
    _bump_epoch!(ws)
    empty!(ws.frontier); empty!(ws.next_frontier)
    empty!(ws.collected_vars); empty!(ws.collected_tensors)

    # seed
    _mark_var!(ws, focus_var)
    push!(ws.frontier, focus_var)
    push!(ws.collected_vars, focus_var)

    # k var-hops
    stopped = false
    @inbounds for _ in 1:k
        stopped = expand_one_var!(tn, ws, max_tensors)
        ws.frontier, ws.next_frontier = ws.next_frontier, ws.frontier
        empty!(ws.next_frontier)
        (stopped || isempty(ws.frontier)) && break
    end

    # classify inner/boundary using current epoch marks for tensor-membership
    inner, boundary = classify_inner_boundary!(tn, ws, ws.collected_vars)

    # deterministic ordering
    sort!(inner); sort!(boundary); sort!(ws.collected_tensors)
    return Region(focus_var, TensorId.(ws.collected_tensors), VarId.(inner), VarId.(boundary))
end