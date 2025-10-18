struct Variable 
    id::Int
    dom_size::Int
    deg::Int
end
function Base.show(io::IO, v::Variable)
    print(io, "Variable($(v.id), dom_size=$(v.dom_size), deg=$(v.deg))")
end

struct EdgeRef
    var::Int  # variable id
    axis::Int  # inside a factor
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
    v2t::Vector{Vector{Int}}  # var id -> tensor ids
    t2v::Vector{Vector{EdgeRef}}
    axis_of_t::Dict{Tuple{Int,Int},Int}
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
    vars_to_tensors = [Int[] for _ in 1:var_num]
    tensors_to_edges = [EdgeRef[] for _ in 1:F]
    for i in 1:F
        var_axes = tensors_to_vars[i]
        @assert length(tensor_data[i]) == 1 << length(var_axes)  "Boolean tensor length mismatch"
        tensors[i] = BoolTensor(i, var_axes, tensor_data[i])
        for (j, v) in enumerate(var_axes)
            push!(vars_to_tensors[v], i)
            push!(tensors_to_edges[i], EdgeRef(v, j))
        end
    end

    axis_of_t = Dict{Tuple{Int,Int},Int}()
    for (fid, tensor) in enumerate(tensors)
        for (axis, vid) in enumerate(tensor.var_axes)
            axis_of_t[(fid, vid)] = axis
        end
    end

    vars = Vector{Variable}(undef, var_num)
    for i in 1:var_num
        vars[i] = Variable(i, 2, length(vars_to_tensors[i]))
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

@inline get_var_value(dms::Vector{DomainMask}, var_id::Int) = has1(dms[var_id]) ? 1 : 0

mutable struct DynamicWorkspace
    cached_doms::Vector{DomainMask}
    has_cached_solution::Bool
end
DynamicWorkspace(var_num::Int) = DynamicWorkspace(Vector{DomainMask}(undef, var_num), false)

struct Region
    id::Int
    tensors::Vector{Int}
    inner_vars::Vector{Int}
    boundary_vars::Vector{Int}
end
function Base.show(io::IO, region::Region)
    print(io, "Region(focus=$(region.id), tensors=$(length(region.tensors)), inner=$(length(region.inner_vars)), boundary=$(length(region.boundary_vars)))")
end

struct TNProblem <: AbstractProblem
    static::TNStatic
    doms::Vector{DomainMask}
    n_unfixed::Int
    ws::DynamicWorkspace
end
function TNProblem(static::TNStatic)::TNProblem
    doms = init_doms(static)
    n_unfixed = length(static.vars)
    ws = DynamicWorkspace(length(static.vars))
    return TNProblem(static, doms, n_unfixed, ws)
end
function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(problem.n_unfixed)/$(length(problem.static.vars)))")
end

get_var_value(problem::TNProblem, var_id::Int) = get_var_value(problem.doms, var_id)
get_var_value(problem::TNProblem, var_ids::Vector{Int}) = Bool[get_var_value(problem.doms, var_id) for var_id in var_ids]

@inline function is_solved(problem::TNProblem)::Bool
    return problem.n_unfixed == 0
end

function cache_branch_solution!(problem::TNProblem)
    ws = problem.ws
    copyto!(ws.cached_doms, problem.doms)
    ws.has_cached_solution = true
    return nothing
end

function reset_last_branch_problem!(problem::TNProblem)
    problem.ws.has_cached_solution = false
    return nothing
end

@inline has_last_branch_problem(problem::TNProblem) = problem.ws.has_cached_solution

function last_branch_problem(problem::TNProblem)
    has_last_branch_problem(problem) || throw(ErrorException("No cached branch solution"))
    doms = copy(problem.ws.cached_doms)
    fixed = count(x -> is_fixed(x), doms)
    @assert fixed == length(doms)
    return TNProblem(problem.static, doms, 0, problem.ws)
end
