struct BooleanInferenceProblem <: AbstractProblem
    tensors::Vector{Vector{Tropical{Float64}}}
    # Hyperedge-to-vertex
    he2v::Vector{Vector{Int}}
    # Vertex-to-hyperedge
    v2he::Vector{Vector{Int}}
    # the total number of variables
    literal_num::Int
end

# Constructor for BooleanInferenceProblem: 
# automatically generate v2he from he2v
BooleanInferenceProblem(tensor::Vector{Vector{Tropical{Float64}}}, he2v::Vector{Vector{Int}}, literal_num::Int) = BooleanInferenceProblem(tensor, he2v, [findall(x -> i in x, he2v) for i in 1:literal_num], literal_num)

Base.copy(p::BooleanInferenceProblem) = BooleanInferenceProblem(copy(p.tensors), copy(p.he2v), copy(p.v2he), p.literal_num)

struct NumOfVertices <: AbstractMeasure end
OptimalBranchingCore.measure(bs::AbstractBranchingStatus, ::NumOfVertices) = -count_ones(bs.decided_mask)

struct NumOfClauses <: AbstractMeasure end
OptimalBranchingCore.measure(bs::AbstractBranchingStatus, ::NumOfClauses) = count(>=(0), bs.undecided_literals)

function initialize_branching_status(p::BooleanInferenceProblem)
    # t is the number of bits needed to represent the branching status
    t = (p.literal_num - 1) ÷ 64 + 1
    return BranchingStatus{t}(LongLongUInt{t}(0), LongLongUInt{t}(0), length.(p.he2v))
end

struct NumOfDegrees <: AbstractMeasure end
OptimalBranchingCore.measure(bs::AbstractBranchingStatus, ::NumOfDegrees) = sum(x -> x > 0 ? x : 0, bs.undecided_literals)

# Weighted measure: sum_i w_i * n_i, where n_i counts edges with i undecided vars.
# Defaults: w0 = 0, w1 = 0, w2 = 0, w3 = 1, w_{i>=4} = 1
struct WeightedClauseArityMeasure <: AbstractMeasure
    w2::Float64
    w3::Float64
end

WeightedClauseArityMeasure() = WeightedClauseArityMeasure(0.0, 1.0)

function OptimalBranchingCore.measure(bs::AbstractBranchingStatus, m::WeightedClauseArityMeasure)
    total = 0.0
    for cnt in bs.undecided_literals
        if cnt <= 1
            continue
        elseif cnt == 2
            total += m.w2
        elseif cnt == 3
            total += m.w3
        else
            total += 1.0
        end
    end
    return total
end