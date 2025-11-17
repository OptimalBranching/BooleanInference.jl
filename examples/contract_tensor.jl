using OMEinsum
using TropicalNumbers: Tropical

const T1 = one(Tropical{Float64})
const T0 = zero(Tropical{Float64})

tensor_and = [
    T1,    # 000
    T0,    # 001
    T1,    # 010
    T0,    # 011
    T1,    # 100
    T0,    # 101
    T0,    # 110
    T1     # 111
]

tensor_or = [
    T1,    # 000
    T0,    # 001
    T0,    # 010
    T1,    # 011
    T0,    # 100
    T1,    # 101
    T0,    # 110
    T1     # 111
]

tensor_xor = [
    T1,    # 000
    T0,    # 001
    T0,    # 010
    T1,    # 011
    T0,    # 100
    T1,    # 101
    T1,    # 110
    T0     # 111
]

function tensor_unwrapping(vec::Vector{T}) where T
    len = length(vec)
    @assert len > 0
    k = trailing_zeros(len)
    @assert (1 << k) == len "vector length is not power-of-two"
    dims = ntuple(_->2, k)
    return reshape(vec, dims)
end

ixs = [[1,2,3], [3,4,5]]
iy = [1,2,3,4,5]
eincode = EinCode(ixs, iy)
optcode = optimize_code(eincode, uniformsize(eincode, 2), GreedyMethod())    
unwrapped_tensors = [tensor_unwrapping(t) for t in [tensor_xor, tensor_xor]]
result = optcode(unwrapped_tensors...)

findall(result .== T1)
