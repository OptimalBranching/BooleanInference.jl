"""
    BooleanInferenceProblem <: AbstractProblem

Static problem definition containing all constraints for Boolean inference.

Fields
- `tensors::Vector{Vector{Tropical{Float64}}}`: Constraint tensor per hyperedge.
  * Each entry corresponds to an assignment of variables
  * `Tropical(0.0)` means feasible; `Tropical(1.0)` means forbidden
- `he2v::Vector{Vector{Int}}`: Hyperedge-to-vertex mapping; `he2v[i]` lists variables in hyperedge i
- `v2he::Vector{Vector{Int}}`: Vertex-to-hyperedge mapping; `v2he[i]` lists hyperedges containing variable i
- `literal_num::Int`: Total number of variables

Difference to BranchingStatus
- `BooleanInferenceProblem`: immutable static definition of the problem
- `BranchingStatus`: dynamic search state (decisions, satisfied/active constraints)
"""
struct BooleanInferenceProblem <: AbstractProblem
    tensors::Vector{Vector{Tropical{Float64}}}
    he2v::Vector{Vector{Int}}  # Hyperedge-to-vertex mapping
    v2he::Vector{Vector{Int}}  # Vertex-to-hyperedge mapping  
    literal_num::Int           # Total number of variables
end

# Constructor: automatically generate v2he from he2v
BooleanInferenceProblem(tensor::Vector{Vector{Tropical{Float64}}}, he2v::Vector{Vector{Int}}, literal_num::Int) = BooleanInferenceProblem(tensor, he2v, [findall(x -> i in x, he2v) for i in 1:literal_num], literal_num)

Base.copy(problem::BooleanInferenceProblem) = BooleanInferenceProblem(copy(problem.tensors), copy(problem.he2v), copy(problem.v2he), problem.literal_num)

"""
Named small-count constants used in return tuples for readability.
"""
const COUNT_NONE = 0
const COUNT_UNIT = 1

"""
    BranchResult

Lightweight immutable container for branch-and-reduce function returns.
Replaces (success::Bool, status::AbstractBranchingStatus, count::Int) tuples.

Fields:
- `success::Bool`: whether the branch succeeded (satisfiable)
- `status::AbstractBranchingStatus`: updated branching status
- `count::Int`: step count for complexity analysis
"""
struct BranchResult{T<:AbstractBranchingStatus}
    success::Bool
    status::T
    count::Int
end

# Convenience constructors
BranchResult(success::Bool, status::AbstractBranchingStatus) = BranchResult(success, status, COUNT_UNIT)
BranchResult(status::AbstractBranchingStatus, count::Int) = BranchResult(true, status, count)

"""
    NumOfVertices <: AbstractMeasure

Measure based on the number of undecided variables.
Returns the negative count of decided variables to guide branching.
Higher is better (smaller remaining problem).
"""
struct NumOfVertices <: AbstractMeasure end
OptimalBranchingCore.measure(branching_status::AbstractBranchingStatus, ::NumOfVertices) = -count_ones(branching_status.decided_mask)

"""
    NumOfClauses <: AbstractMeasure

Measure based on number of active constraints.
Counts constraints with `undecided_literals >= 0`.
"""
struct NumOfClauses <: AbstractMeasure end
OptimalBranchingCore.measure(branching_status::AbstractBranchingStatus, ::NumOfClauses) = count(>=(0), branching_status.undecided_literals)

"""
    initialize_branching_status(problem::BooleanInferenceProblem)

Initialize `BranchingStatus` from a Boolean inference problem.

Parameters
- `problem`: BooleanInferenceProblem instance

Returns
- `BranchingStatus`: all variables undecided, constraints in initial state
"""
function initialize_branching_status(problem::BooleanInferenceProblem)
    # t is the number of 64-bit blocks needed to represent the branching status
    t = (problem.literal_num - 1) ÷ 64 + 1
    return BranchingStatus{t}(LongLongUInt{t}(0), LongLongUInt{t}(0), length.(problem.he2v))
end

"""
    NumOfDegrees <: AbstractMeasure

Measure based on total undecided-variable degrees across active constraints.
"""
struct NumOfDegrees <: AbstractMeasure end
OptimalBranchingCore.measure(branching_status::AbstractBranchingStatus, ::NumOfDegrees) = sum(x -> x > 0 ? x : 0, branching_status.undecided_literals)

"""
    WeightedClauseArityMeasure <: AbstractMeasure

Weighted measure over constraint arity.
Computes sum_i w_i * n_i where n_i counts constraints with i undecided variables.

Fields
- `w2::Float64`: weight for arity-2 constraints (default 0.0)
- `w3::Float64`: weight for arity-3 constraints (default 1.0)

Weight policy
- w0 = 0 (satisfied constraints ignored)
- w1 = 0 (unit constraints handled by unit propagation)
- w2 = w2 (2-SAT is efficiently solvable)
- w3 = w3 (3-ary constraints start to be hard)
- w4+ = 1.0 (higher arity constraints)
"""
struct WeightedClauseArityMeasure <: AbstractMeasure
    w2::Float64  # Weight for constraints with 2 undecided variables  
    w3::Float64  # Weight for constraints with 3 undecided variables
end

WeightedClauseArityMeasure() = WeightedClauseArityMeasure(0.0, 1.0)

function OptimalBranchingCore.measure(branching_status::AbstractBranchingStatus, measure::WeightedClauseArityMeasure)
    total = 0.0
    for constraint_arity in branching_status.undecided_literals
        if constraint_arity <= 1
            continue  # Satisfied or unit constraints: weight 0
        elseif constraint_arity == 2
            total += measure.w2
        elseif constraint_arity == 3
            total += measure.w3
        else
            total += 1.0  # Higher arity constraints: weight 1.0
        end
    end
    return total
end

