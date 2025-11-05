struct DomainMask
    bits::UInt8
end

const DM_BOTH = DomainMask(0x03)
const DM_0 = DomainMask(0x01)
const DM_1 = DomainMask(0x02)

@inline is_fixed(dm::DomainMask) = (dm.bits == 0x01) || (dm.bits == 0x02)
@inline has0(dm::DomainMask)::Bool = (dm.bits & 0x01) != 0
@inline has1(dm::DomainMask)::Bool = (dm.bits & 0x02) != 0
function get_var_value(dms::Vector{DomainMask}, var_id::Int)
    dm = dms[var_id]
    dm.bits == 0x01 && return 0
    dm.bits == 0x02 && return 1
    return -1  # not fixed
end

init_doms(static::TNStatic) = fill(DM_BOTH, length(static.vars))

@inline has_contradiction(doms::Vector{DomainMask}) = any(dm -> dm.bits == 0x00, doms)