@inline function get_unfixed_vars(doms::Vector{DomainMask})::Vector{Int}
    unfixed_vars = Int[]
    @inbounds for (i, dm) in enumerate(doms)
        if !is_fixed(dm)
            push!(unfixed_vars, i)
        end
    end
    return unfixed_vars
end

# Convenience: compute number of unfixed variables quickly.
@inline function count_unfixed(doms::Vector{DomainMask})::Int
    c::Int = 0
    @inbounds for dm in doms
        if !is_fixed(dm)
            c += 1
        end
    end
    return c
end

bits_to_int(v::Vector{Bool}) = sum(b << (i - 1) for (i, b) in enumerate(v))

# Memory pool management for reducing allocations
@inline function get_doms_from_pool!(ws::DynamicWorkspace, template::Vector{DomainMask})
    if isempty(ws.doms_pool)
        return copy(template)
    else
        doms = pop!(ws.doms_pool)
        resize!(doms, length(template))
        copyto!(doms, template)
        return doms
    end
end

@inline function return_doms_to_pool!(ws::DynamicWorkspace, doms::Vector{DomainMask})
    length(ws.doms_pool) < 100 && push!(ws.doms_pool, doms)  # Limit pool size to avoid unbounded growth
    return nothing
end

@inline function get_intvec_from_pool!(ws::DynamicWorkspace)
    if isempty(ws.changed_vars_pool)
        return Int[]
    else
        vec = pop!(ws.changed_vars_pool)
        empty!(vec)
        return vec
    end
end

@inline function return_intvec_to_pool!(ws::DynamicWorkspace, vec::Vector{Int})
    length(ws.changed_vars_pool) < 100 && push!(ws.changed_vars_pool, vec)
    return nothing
end