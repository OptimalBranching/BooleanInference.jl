struct VarId ; id::Int32; end
struct TensorId ; id::Int32; end
# Base.Int(v::VarId) = Int(v.id)
# Base.Int(f::TensorId) = Int(f.id)
function Base.show(io::IO, vid::VarId)
    print(io, "VarId($(vid.id))")
end
function Base.show(io::IO, tid::TensorId)
    print(io, "TensorId($(tid.id))")
end

struct Variable 
    id::VarId
    dom_size::Int32
    deg::Int32
end
function Base.show(io::IO, v::Variable)
    print(io, "Variable($(v.id), dom_size=$(v.dom_size), deg=$(v.deg))")
end

struct EdgeRef
    var::VarId
    axis::Int16  # inside a factor
end
function Base.show(io::IO, e::EdgeRef)
    print(io, "EdgeRef($(e.var), axis=$(e.axis))")
end

struct BoolTensor
    id::TensorId
    var_axes::Vector{VarId}
    tensor::Vector{Tropical{Float64}}
end

function Base.show(io::IO, f::BoolTensor)
    print(io, "BoolTensor($(f.id), vars=[$(join([v.id for v in f.var_axes], ", "))], size=$(length(f.tensor)))")
end

# struct DenseTropicalTensor{T, N}
#     data::Vector{T}  # length == prod(shape)
#     shape::NTuple{N, Int32}  # per-axis domain size
#     strides::NTuple{N, Int32}  # column-major strides
# end

# @inline function compute_strides(shape::NTuple{N, Int32}) where {N}
#     nd = length(shape)  # number of dimensions
#     s = Vector{Int32}(undef, nd)
#     stride = Int32(1)
#     @inbounds for i in 1:nd
#         s[i] = stride
#         stride *= shape[i]
#     end
#     return s
# end

# @inline function linindex(strides::NTuple{N, Int32}, coords::NTuple{N,Int32}) where {N}
#     idx = Int32(1)
#     @inbounds for i in 1:N
#         idx += (coords[i]-Int32(1))*strides[i]
#     end
#     return Int(idx)
# end

struct TNStatic
    vars::Vector{Variable}
    tensors::Vector{BoolTensor}
    v2t::Vector{Vector{TensorId}}
    t2v::Vector{Vector{EdgeRef}}
    axis_of_t::Dict{Tuple{Int32,Int32},Int16}
end

function Base.show(io::IO, tn::TNStatic)
    print(io, "TNStatic(vars=$(length(tn.vars)), tensors=$(length(tn.tensors)))")
end

function Base.show(io::IO, ::MIME"text/plain", tn::TNStatic)
    println(io, "TNStatic:")
    println(io, "  variables: $(length(tn.vars))")
    println(io, "  tensors: $(length(tn.tensors))")
    println(io, "  variable-tensor incidence: $(length(tn.v2t))")
    println(io, "  tensor-variable incidence: $(length(tn.t2v))")
    println(io, "  axis mappings: $(length(tn.axis_of_t))")
end

function setup_problem(var_num::Int,
                       tensors_to_vars::Vector{Vector{Int}},
                       tensor_data::Vector{Vector{Tropical{Float64}}})
    F = length(tensors_to_vars)
    tensors = Vector{BoolTensor}(undef, F)
    vars_to_tensors = [TensorId[] for _ in 1:var_num]
    tensors_to_edges = [EdgeRef[] for _ in 1:F]
    for i in 1:F
        var_axes = VarId.(Int32.(tensors_to_vars[i]))
        @assert length(tensor_data[i]) == 1 << length(var_axes)  "Boolean tensor length mismatch"
        tensors[i] = BoolTensor(TensorId(Int32(i)), var_axes, tensor_data[i])
        for (j, v) in enumerate(var_axes)
            push!(vars_to_tensors[v.id], TensorId(Int32(i)))
            push!(tensors_to_edges[i], EdgeRef(v, Int16(j)))
        end
    end

    axis_of_t = Dict{Tuple{Int32,Int32},Int16}()
    for (fid, tensor) in enumerate(tensors)
        for (axis, vid) in enumerate(tensor.var_axes)
            axis_of_t[(Int32(fid), vid.id)] = Int16(axis)
        end
    end

    vars = Vector{Variable}(undef, var_num)
    for i in 1:var_num
        vars[i] = Variable(VarId(Int32(i)), Int32(2), length(vars_to_tensors[i]))
    end

    return TNStatic(vars, tensors, vars_to_tensors, tensors_to_edges, axis_of_t)
end

function setup_from_tensor_network(tn)::TNStatic
    t2v = getixsv(tn.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), tn)
    vec_tensors = [vec(t) for t in tensors]
    new_tensors = [replace(t, Tropical(1.0) => zero(Tropical{Float64})) for t in vec_tensors]
    return setup_problem(length(tn.problem.symbols), t2v, new_tensors)
end

struct DomainMask
    bits::UInt8
end
const DM_BOTH = DomainMask(0x03)
const DM_0 = DomainMask(0x01)
const DM_1 = DomainMask(0x02)

@inline is_fixed(dm::DomainMask) = (dm.bits == 0x01) | (dm.bits == 0x02)
@inline has0(dm::DomainMask)::Bool = (dm.bits & 0x01) != 0
@inline has1(dm::DomainMask)::Bool = (dm.bits & 0x02) != 0

function init_doms(static::TNStatic)
    return fill(DM_BOTH, length(static.vars))
end

mutable struct HopWorkspace
    epoch::Int32
    visited_vars::Vector{Int32}
    visited_tensors::Vector{Int32}

    frontier::Vector{Int32}
    next_frontier::Vector{Int32}
    
    collected_vars::Vector{Int32}
    collected_tensors::Vector{Int32}
end

function HopWorkspace(var_num::Int, tensor_num::Int)
    return HopWorkspace(Int32(1), fill(Int32(0), var_num), fill(Int32(0), tensor_num), Int32[], Int32[], Int32[], Int32[])
end

struct Region
    id::Int32
    tensors::Vector{TensorId}
    inner_vars::Vector{VarId}
    boundary_vars::Vector{VarId}
end
function Base.show(io::IO, region::Region)
    print(io, "Region(focus=$(region.id), tensors=$(length(region.tensors)), inner=$(length(region.inner_vars)), boundary=$(length(region.boundary_vars)))")
end

struct TNProblem <: AbstractProblem
    static::TNStatic
    doms::Vector{DomainMask}
    n_unfixed::Int32
    ws::HopWorkspace
end
function TNProblem(static::TNStatic)::TNProblem
    doms = init_doms(static)
    n_unfixed = Int32(length(static.vars))
    ws = HopWorkspace(length(static.vars), length(static.tensors))
    return TNProblem(static, doms, n_unfixed, ws)
end
function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(problem.n_unfixed)/$(length(problem.static.vars)))")
end

@inline function is_solved(problem::TNProblem)::Bool
    return problem.n_unfixed == 0
end