@enum DomainMask::UInt8 begin
    DM_NONE = 0x00
    DM_0 = 0x01
    DM_1 = 0x02
    DM_BOTH = 0x03
end

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
    return -1  # not fixed
end

function is_hard(tn::BipartiteGraph, doms::Vector{DomainMask}, tensor_id::Int)
    vars = tn.tensors[tensor_id].var_axes
    degree = 0
    @inbounds for var_id in vars
        !is_fixed(doms[var_id]) && (degree += 1)
    end
    # @show degree
    return degree > 2
end

init_doms(static::BipartiteGraph) = fill(DM_BOTH, length(static.vars))

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

# Concrete type for cached branch results (used in DynamicWorkspace)
# This must be defined before workspace.jl is loaded
struct BranchCacheEntry
    doms::Vector{DomainMask}
    n_unfixed::Int
    local_value::Int
    assignments::Vector{Tuple{Int,Bool}}  # Branching decisions (clause assignments)
end