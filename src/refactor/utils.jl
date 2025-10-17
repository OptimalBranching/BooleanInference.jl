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