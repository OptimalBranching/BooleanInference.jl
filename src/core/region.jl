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

function get_region_tensor_type(problem::TNProblem, region::Region)
    symbols = Symbol[]
    fanin = Vector{Int}[]
    fanout = Vector{Int}[]
    active_vars = get_unfixed_vars(problem, region.tensors)
    for tensor_id in region.tensors
        push!(symbols, problem.static.tensor_symbols[tensor_id])
        push!(fanin, problem.static.tensor_fanin[tensor_id])
        push!(fanout, problem.static.tensor_fanout[tensor_id])
    end
    return symbols, fanin, fanout, active_vars
end

