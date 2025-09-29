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


# Search statistics tracker
mutable struct SearchStatistics
    branch_count::Int            # number of branches
    node_count::Int              # number of visited nodes
    satisfiable_branches::Int    # count of satisfiable leaf branches
    unsatisfiable_branches::Int  # count of unsatisfiable leaf branches
    two_sat_applications::Int    # number of 2-SAT reductions applied
    max_depth::Int               # maximum search depth
    
    SearchStatistics() = new(0, 0, 0, 0, 0, 0)
end

Base.copy(stats::SearchStatistics) = SearchStatistics(stats.branch_count, stats.node_count, 
    stats.satisfiable_branches, stats.unsatisfiable_branches, stats.two_sat_applications, stats.max_depth)

function increment_branches!(stats::SearchStatistics)
    stats.branch_count += 1
end

function increment_nodes!(stats::SearchStatistics)
    stats.node_count += 1
end

function increment_satisfiable!(stats::SearchStatistics)
    stats.satisfiable_branches += 1
end

function increment_unsatisfiable!(stats::SearchStatistics)
    stats.unsatisfiable_branches += 1
end

function increment_two_sat!(stats::SearchStatistics)
    stats.two_sat_applications += 1
end

function update_max_depth!(stats::SearchStatistics, depth::Int)
    stats.max_depth = max(stats.max_depth, depth)
end

function Base.show(io::IO, stats::SearchStatistics)
    println(io, "Search statistics:")
    println(io, "  Branches: $(stats.branch_count)")
    println(io, "  Nodes: $(stats.node_count)")
    println(io, "  Satisfiable leaves: $(stats.satisfiable_branches)")
    println(io, "  Unsatisfiable leaves: $(stats.unsatisfiable_branches)")
    println(io, "  2-SAT applications: $(stats.two_sat_applications)")
    println(io, "  Max depth: $(stats.max_depth)")
end

# Debug system
@enum DebugLevel begin
    DEBUG_OFF = 0
    DEBUG_BASIC = 1       # basic: function enter/exit
    DEBUG_DETAILED = 2    # detailed: branching decisions, constraint status
    DEBUG_VERBOSE = 3     # verbose: all intermediate steps
end

mutable struct DebugConfig
    level::DebugLevel
    show_depth::Bool           # whether to print search depth
    show_branching_status::Bool  # whether to print detailed branching status
    show_statistics::Bool      # whether to print stats live
end

DebugConfig(level::DebugLevel = DEBUG_OFF) = DebugConfig(level, true, false, false)

# Global debug config
const DEBUG_CONFIG = Ref(DebugConfig())

"""
    set_debug_level!(level::DebugLevel; show_depth=true, show_branching_status=false, show_statistics=false)

Configure debug level and options.
"""
function set_debug_level!(level::DebugLevel; show_depth=true, show_branching_status=false, show_statistics=false)
    DEBUG_CONFIG[] = DebugConfig(level, show_depth, show_branching_status, show_statistics)
end

"""
    debug_log(level::DebugLevel, message::String, depth::Int=0; prefix="")

Print debug message if current debug level >= level.
"""
function debug_log(level::DebugLevel, message::String, depth::Int=0; prefix="")
    config = DEBUG_CONFIG[]
    if config.level >= level
        indent = config.show_depth ? "  " ^ depth : ""
        full_prefix = isempty(prefix) ? "" : "[$prefix] "
        println("$(indent)$(full_prefix)$(message)")
    end
end

"""
    debug_branching_status(bs::AbstractBranchingStatus, problem::BooleanInferenceProblem, depth::Int=0)

Print a compact view of branching status for debugging.
"""
function debug_branching_status(bs::AbstractBranchingStatus, problem::BooleanInferenceProblem, depth::Int=0)
    config = DEBUG_CONFIG[]
    if config.level >= DEBUG_DETAILED && config.show_branching_status
        decided_count = count_ones(bs.decided_mask)
        undecided_count = problem.literal_num - decided_count
        active_constraints = count(x -> x > 0, bs.undecided_literals)
        satisfied_constraints = count(x -> x == -1, bs.undecided_literals)
        
        debug_log(DEBUG_DETAILED, "State: decided=$decided_count, undecided=$undecided_count", depth; prefix="STATE")
        debug_log(DEBUG_DETAILED, "Constraints: active=$active_constraints, satisfied=$satisfied_constraints", depth; prefix="CONSTRAINTS")
    end
end