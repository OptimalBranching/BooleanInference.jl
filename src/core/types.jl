struct Variable 
    id::Int
    dom_size::Int
    deg::Int
end

function Base.show(io::IO, v::Variable)
    print(io, "Variable($(v.id), dom_size=$(v.dom_size), deg=$(v.deg))")
end

struct EdgeRef
    var::Int
    axis::Int
end

function Base.show(io::IO, e::EdgeRef)
    print(io, "EdgeRef($(e.var), axis=$(e.axis))")
end

struct BoolTensor
    id::Int
    var_axes::Vector{Int}
    tensor::Vector{Tropical{Float64}}
end

function Base.show(io::IO, f::BoolTensor)
    print(io, "BoolTensor($(f.id), vars=[$(join(f.var_axes, ", "))], size=$(length(f.tensor)))")
end

struct TensorMasks
    sat::BitVector
    axis_masks0::Vector{BitVector}
    axis_masks1::Vector{BitVector}
end

# Build support masks for a tensor by enumerating all configurations.
function build_tensor_masks(tensor::BoolTensor)
    nvars = length(tensor.var_axes)
    n_cfg = 1 << nvars

    sat = falses(n_cfg)
    axis_masks0 = [falses(n_cfg) for _ in 1:nvars]
    axis_masks1 = [falses(n_cfg) for _ in 1:nvars]

    @inbounds for cfg in 0:(n_cfg-1)
        # Check if this configuration satisfies the constraint
        if tensor.tensor[cfg+1] == Tropical(0.0)  # one(Tropical{Float64})
            sat[cfg+1] = true
        end

        # Record which value each variable takes in this config
        @inbounds for axis in 1:nvars
            bit = (cfg >> (axis - 1)) & 1
            if bit == 0
                axis_masks0[axis][cfg+1] = true
            else
                axis_masks1[axis][cfg+1] = true
            end
        end
    end
    return TensorMasks(sat, axis_masks0, axis_masks1)
end

