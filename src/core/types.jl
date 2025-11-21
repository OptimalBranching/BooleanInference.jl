struct Variable
    deg::Int
end

function Base.show(io::IO, v::Variable)
    print(io, "Variable(deg=$(v.deg))")
end

struct BoolTensor
    var_axes::Vector{Int}
    tensor::Vector{Tropical{Float64}}
end

function Base.show(io::IO, f::BoolTensor)
    print(io, "BoolTensor(vars=[$(join(f.var_axes, ", "))], size=$(length(f.tensor)))")
end


