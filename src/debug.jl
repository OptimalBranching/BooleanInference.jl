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

Base.copy(stats::SearchStatistics) = SearchStatistics(stats.branch_count,
                                                    stats.node_count,
                                                    stats.satisfiable_branches, 
                                                    stats.unsatisfiable_branches, 
                                                    stats.two_sat_applications, 
                                                    stats.max_depth)

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

DebugConfig(level::DebugLevel=DEBUG_OFF) = DebugConfig(level, true, false, false)

# Global debug config
const DEBUG_CONFIG = Ref(DebugConfig())

"""
    debug_enabled(level::DebugLevel) -> Bool

Fast check for whether logging at `level` should be emitted.
"""
@inline function debug_enabled(level::DebugLevel)
    return DEBUG_CONFIG[].level >= level
end

"""
    set_debug_level!(level::DebugLevel; show_depth=true, show_branching_status=false, show_statistics=false)

Configure debug level and options.
"""
function set_debug_level!(level::DebugLevel; show_depth=true, show_branching_status=false, show_statistics=false)
    DEBUG_CONFIG[] = DebugConfig(level, show_depth, show_branching_status, show_statistics)
end

"""
    debug_log(level::DebugLevel, message::String, depth::Int=0; prefix="")

Eager logger variant used by the @dbg macro after level check.
"""
function debug_log(level::DebugLevel, message::String, depth::Int=0; prefix="")
    if debug_enabled(level)
        indent = DEBUG_CONFIG[].show_depth ? "  "^depth : ""
        full_prefix = isempty(prefix) ? "" : "[$prefix] "
        println("$(indent)$(full_prefix)$(message)")
    end
end

# """
#     debug_log(level::DebugLevel, f::Function, depth::Int=0; prefix="")

# Lazy logger version. The function `f` is only evaluated if logging at `level` is enabled.
# """
# function debug_log(level::DebugLevel, f::Function, depth::Int=0; prefix="")
#     if debug_enabled(level)
#         debug_log(level, f(), depth; prefix=prefix)
#     end
# end

"""
    @dbg level depth prefix msg

Emit a debug log at compile-time guarded level. The `msg` expression
is only evaluated when the current debug level is >= `level`.
"""
macro dbg(level, depth, prefix, msg)
    return :( if debug_enabled($(esc(level)))
                  debug_log($(esc(level)), $(esc(msg)), $(esc(depth)); prefix=$(esc(prefix)))
              end )
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

        @dbg DEBUG_DETAILED depth "STATE" "State: decided=$(decided_count), undecided=$(undecided_count)"
        @dbg DEBUG_DETAILED depth "CONSTRAINTS" "Constraints: active=$(active_constraints), satisfied=$(satisfied_constraints)"
    end
end