abstract type AbstractBranchingStatus{C} end
struct BranchingStatus{C} <: AbstractBranchingStatus{C}
    config::LongLongUInt{C}
    decided_mask::LongLongUInt{C}
    undecided_literals::Vector{Int} # undecided literals in each clause, 0 means unsatisfiable, -1 means already satisfied
end

Base.:+(bs1::BranchingStatus, bs2::BranchingStatus) = BranchingStatus(bs1.config, bs1.decided_mask, bs1.undecided_literals)

struct BranchingStatusBranchCount{C} <: AbstractBranchingStatus{C}
    config::LongLongUInt{C}
    decided_mask::LongLongUInt{C}
    undecided_literals::Vector{Int} # undecided literals in each clause, 0 means unsatisfiable, -1 means already satisfied
    count::Int
end

Base.:+(bs1::BranchingStatusBranchCount, bs2::BranchingStatusBranchCount) = BranchingStatusBranchCount(bs1.config, bs1.decided_mask, bs1.undecided_literals, bs1.count + bs2.count)
function get_answer(bs::BranchingStatus,n::Int)
    return [Int(readbit(bs.config,i)) for i in 1:n]
end