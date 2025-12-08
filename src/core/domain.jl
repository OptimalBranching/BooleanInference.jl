@enum DomainMask::UInt8 begin
    DM_NONE = 0x00
    DM_0 = 0x01
    DM_1 = 0x02
    DM_BOTH = 0x03
end

init_doms(static::BipartiteGraph) = fill(DM_BOTH, length(static.vars))
# Get the underlying bits value
@inline bits(dm::DomainMask)::UInt8 = UInt8(dm)

# Convert UInt8 to DomainMask (allows any UInt8 value, not just enum values)
Base.convert(::Type{DomainMask}, bits::UInt8) = reinterpret(DomainMask, bits)

@inline is_fixed(dm::DomainMask) = (dm == DM_0) || (dm == DM_1)
@inline has0(dm::DomainMask)::Bool = (bits(dm) & 0x01) != 0
@inline has1(dm::DomainMask)::Bool = (bits(dm) & 0x02) != 0

function get_var_value(dms::Vector{DomainMask}, var_id::Int)
    dm = dms[var_id]
    dm == DM_0 && return 0
    dm == DM_1 && return 1
    @assert false "Variable $var_id is not fixed"
end
function get_var_value(dms::Vector{DomainMask}, var_ids::Vector{Int})
    return Bool[get_var_value(dms, var_id) for var_id in var_ids]
end

function active_degree(tn::BipartiteGraph, doms::Vector{DomainMask})
    degree = zeros(Int, length(tn.tensors))
    @inbounds for (tensor_id, tensor) in enumerate(tn.tensors)
        vars = tensor.var_axes
        degree[tensor_id] = sum(!is_fixed(doms[var_id]) for var_id in vars)
    end
    return degree
end
is_hard(tn::BipartiteGraph, doms::Vector{DomainMask}) = active_degree(tn, doms) .> 2

@inline has_contradiction(doms::Vector{DomainMask}) = any(dm -> dm == DM_NONE, doms)

const DOMAIN_MASK_NAMES = ("NONE", "0", "1", "BOTH")

function Base.show(io::IO, dm::DomainMask)
    if 1 <= bits(dm) + 1 <= length(DOMAIN_MASK_NAMES)
        @inbounds print(io, DOMAIN_MASK_NAMES[bits(dm) + 1])
    else
        print(io, "UNDEF")
    end
end

function Base.show(io::IO, ::MIME"text/plain", dm::DomainMask)
    if 1 <= bits(dm) + 1 <= length(DOMAIN_MASK_NAMES)
        @inbounds print(io, DOMAIN_MASK_NAMES[bits(dm) + 1])
    else
        print(io, "UNDEF")
    end
end