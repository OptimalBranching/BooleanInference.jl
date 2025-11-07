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

init_doms(static::TNStatic) = fill(DM_BOTH, length(static.vars))

@inline has_contradiction(doms::Vector{DomainMask}) = any(dm -> dm == DM_NONE, doms)