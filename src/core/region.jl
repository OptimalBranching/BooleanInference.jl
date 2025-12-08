struct Region
    id::Int
    tensors::Vector{Int}
    vars::Vector{Int}
end

function Base.show(io::IO, region::Region)
    print(io, "Region(focus=$(region.id), tensors=$(region.tensors), vars=$(region.vars))")
end

function Base.copy(region::Region)
    return Region(region.id, region.tensors, region.vars)
end
