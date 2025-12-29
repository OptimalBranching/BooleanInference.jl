# Zero-overhead structured diagnostics for branching decisions
# Design: Use type dispatch to enable/disable logging at compile time
#
# Usage:
#   logger = NoLogger()           # No overhead, all logging calls compile to nothing
#   logger = BranchingLogger()    # Full logging, stores all decision logs
#
# The logger is passed through SearchContext, so enabling/disabling is a single change.

# ============================================================================
# Logger trait: controls whether logging is enabled
# ============================================================================

abstract type AbstractLogger end

"""No-op logger - all logging calls compile to nothing (zero overhead)."""
struct NoLogger <: AbstractLogger end

# ============================================================================
# BranchingLog: per-decision structured log entry
# (Must be defined before BranchingLogger which uses it)
# ============================================================================

"""
Structured log for a single branching decision.
Contains all diagnostic quantities needed for paper analysis.
"""
mutable struct BranchingLog
    # Region basic quantities
    region_var_count::Int          # |V_R| - number of variables in region
    region_tensor_count::Int       # |T_R| - number of tensors in region
    boundary_var_count::Int        # |∂R| - variables connected outside region

    # Support statistics
    support_size::Int              # Number of feasible configurations
    forced_assignments::Int        # Variables fixed by propagation

    # Propagation cost
    prop_time_ns::UInt64           # Propagation time in nanoseconds

    # Branch effect
    branch_count::Int              # Number of branches generated
    subproblem_measures::Vector{Float64}  # Measure value for each branch

    # Depth tracking
    depth::Int                     # Current search tree depth
end

function BranchingLog()
    return BranchingLog(0, 0, 0, 0, 0, UInt64(0), 0, Float64[], 0)
end

# ============================================================================
# BranchingLogger: active logger that records all decisions
# ============================================================================

"""Active logger that records all branching decisions."""
mutable struct BranchingLogger <: AbstractLogger
    logs::Vector{BranchingLog}
    total_prop_time_ns::UInt64
    total_region_vars::Int
    total_region_tensors::Int
    total_branches::Int
end

BranchingLogger() = BranchingLogger(BranchingLog[], UInt64(0), 0, 0, 0)

function reset!(logger::BranchingLogger)
    empty!(logger.logs)
    logger.total_prop_time_ns = UInt64(0)
    logger.total_region_vars = 0
    logger.total_region_tensors = 0
    logger.total_branches = 0
    return logger
end
reset!(::NoLogger) = nothing

# ============================================================================
# Logging API: Compile-time dispatch for zero overhead
# ============================================================================

# All NoLogger methods are no-ops that should inline to nothing
@inline new_log!(::NoLogger, ::Int) = nothing
@inline log_region!(::NoLogger, ::Any, ::Any) = nothing
@inline log_support!(::NoLogger, ::Int) = nothing
@inline log_prop_time!(::NoLogger, ::UInt64) = nothing
@inline log_branch_count!(::NoLogger, ::Int) = nothing
@inline log_subproblem_measure!(::NoLogger, ::Float64) = nothing
@inline log_forced_assignments!(::NoLogger, ::Int) = nothing
@inline finish_log!(::NoLogger) = nothing

# BranchingLogger methods do actual work
@inline function new_log!(logger::BranchingLogger, depth::Int)
    log = BranchingLog()
    log.depth = depth
    push!(logger.logs, log)
    return nothing
end

@inline function current_log(logger::BranchingLogger)
    return logger.logs[end]
end

@inline function log_region!(logger::BranchingLogger, region, boundary_count::Int)
    log = current_log(logger)
    log.region_var_count = length(region.vars)
    log.region_tensor_count = length(region.tensors)
    log.boundary_var_count = boundary_count
    logger.total_region_vars += log.region_var_count
    logger.total_region_tensors += log.region_tensor_count
    return nothing
end

@inline function log_support!(logger::BranchingLogger, support_size::Int)
    current_log(logger).support_size = support_size
    return nothing
end

@inline function log_prop_time!(logger::BranchingLogger, time_ns::UInt64)
    log = current_log(logger)
    log.prop_time_ns += time_ns
    logger.total_prop_time_ns += time_ns
    return nothing
end

@inline function log_branch_count!(logger::BranchingLogger, count::Int)
    current_log(logger).branch_count = count
    logger.total_branches += count
    return nothing
end

@inline function log_subproblem_measure!(logger::BranchingLogger, measure_val::Float64)
    push!(current_log(logger).subproblem_measures, measure_val)
    return nothing
end

@inline function log_forced_assignments!(logger::BranchingLogger, count::Int)
    current_log(logger).forced_assignments = count
    return nothing
end

@inline function finish_log!(::BranchingLogger)
    # Hook for any finalization, currently no-op
    return nothing
end

# ============================================================================
# Summary and export functions
# ============================================================================

function print_logger_summary(logger::BranchingLogger; io::IO=stdout)
    isempty(logger.logs) && return

    n = length(logger.logs)
    println(io, "=== Branching Diagnostics Summary ===")
    println(io, "Total logged decisions: ", n)
    println(io, "Total propagation time: ", round(logger.total_prop_time_ns / 1e6, digits=2), " ms")

    avg_region_vars = logger.total_region_vars / n
    avg_region_tensors = logger.total_region_tensors / n
    avg_branches = logger.total_branches / n

    println(io, "Average region size: ", round(avg_region_vars, digits=1), " vars, ",
        round(avg_region_tensors, digits=1), " tensors")
    println(io, "Average branches per decision: ", round(avg_branches, digits=2))

    # Support size distribution
    support_sizes = [log.support_size for log in logger.logs]
    println(io, "Support size: min=", minimum(support_sizes), ", max=", maximum(support_sizes),
        ", median=", round(Int, median(support_sizes)))
end

print_logger_summary(::NoLogger; io::IO=stdout) = nothing

"""Export logs to a vector of NamedTuples for analysis."""
function export_logs(logger::BranchingLogger)
    return [(
        depth=log.depth,
        region_vars=log.region_var_count,
        region_tensors=log.region_tensor_count,
        boundary_vars=log.boundary_var_count,
        support_size=log.support_size,
        forced_assignments=log.forced_assignments,
        prop_time_ns=log.prop_time_ns,
        branch_count=log.branch_count,
        subproblem_measures=copy(log.subproblem_measures)
    ) for log in logger.logs]
end

export_logs(::NoLogger) = NamedTuple[]
