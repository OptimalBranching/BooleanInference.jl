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


struct DomainBV
    bv0::BitVector
    bv1::BitVector
end

DomainBV(n::Int) = DomainBV(trues(n), trues(n))  # all BOTH

@inline has0(dbv::DomainBV, i) = dbv.bv0[i]
@inline has1(dbv::DomainBV, i) = dbv.bv1[i]
@inline is_fixed(dbv::DomainBV, i) = dbv.bv0[i] ⊻ dbv.bv1[i]
@inline value_if_fixed(dbv::DomainBV, i)::Int8 = dbv.bv0[i] ⊻ dbv.bv1[i] ? (dbv.bv1[i] ? 1 : 0) : -1

@inline fix0!(dbv::DomainBV, i) = (dbv.bv0[i]=true; dbv.bv1[i]=false)
@inline fix1!(dbv::DomainBV, i) = (dbv.bv0[i]=false; dbv.bv1[i]=true)
@inline remove0!(dbv::DomainBV, i) = (dbv.bv0[i]=false)
@inline remove1!(dbv::DomainBV, i) = (dbv.bv1[i]=false)

@inline fix0_mask!(dbv::DomainBV, mask::BitVector) = (dbv.bv0 .|= mask; dbv.bv1 .&= .!mask)
@inline fix1_mask!(dbv::DomainBV, mask::BitVector) = (dbv.bv1 .|= mask; dbv.bv0 .&= .!mask)
@inline remove0_mask!(dbv::DomainBV, mask::BitVector) = (dbv.bv0 .&= .!mask)
@inline remove1_mask!(dbv::DomainBV, mask::BitVector) = (dbv.bv1 .&= .!mask)

@inline has_contradiction(dbv::DomainBV)::Bool = any(.!dbv.bv0 .& .!dbv.bv1)