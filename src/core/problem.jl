# Result type for branch-and-reduce solving
struct Result
    found::Bool
    solution::Vector{DomainMask}
    stats::BranchingStats
end

function Base.show(io::IO, r::Result)
    if r.found
        print(io, "Result(found=true, solution=available)")
    else
        print(io, "Result(found=false)")
    end
end

struct SolverBuffer
    touched_tensors::Vector{Int}  # Tensors that need propagation
    in_queue::BitVector           # Track which tensors are queued for processing
    scratch_doms::Vector{DomainMask}  # Temporary domain storage for propagation
    branching_cache::Dict{Clause{UInt64}, Vector{DomainMask}}  # Cache propagated domains for branching configurations
end

function SolverBuffer(cn::ConstraintNetwork)
    n_tensors = length(cn.tensors)
    n_vars = length(cn.vars)
    SolverBuffer(
        sizehint!(Int[], n_tensors),
        falses(n_tensors),
        Vector{DomainMask}(undef, n_vars),
        Dict{Clause{UInt64}, Vector{DomainMask}}()
    )
end

struct TNProblem <: AbstractProblem
    static::ConstraintNetwork
    doms::Vector{DomainMask}
    stats::BranchingStats
    buffer::SolverBuffer

    # Internal constructor: final constructor that creates the instance
    function TNProblem(
        static::ConstraintNetwork,
        doms::Vector{DomainMask},
        stats::BranchingStats,
        buffer::SolverBuffer
    )
        new(static, doms, stats, buffer)
    end
end

# Constructor 1: Initialize from ConstraintNetwork (auto-propagate)
function TNProblem(static::ConstraintNetwork)
    buffer = SolverBuffer(static)
    doms = propagate(static, init_doms(static), collect(1:length(static.tensors)), buffer)
    has_contradiction(doms) && error("Domain has contradiction")
    return TNProblem(static, doms, BranchingStats(), buffer)
end

# Constructor 2: Create with explicit domains (creates new buffer)
function TNProblem(
    static::ConstraintNetwork,
    doms::Vector{DomainMask},
    stats::BranchingStats=BranchingStats()
)
    buffer = SolverBuffer(static)
    return TNProblem(static, doms, stats, buffer)
end

function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(count_unfixed(problem))/$(length(problem.static.vars)))")
end

get_var_value(problem::TNProblem, var_id::Int) = get_var_value(problem.doms, var_id)
get_var_value(problem::TNProblem, var_ids::Vector{Int}) = Bool[get_var_value(problem.doms, var_id) for var_id in var_ids]

count_unfixed(problem::TNProblem) = count_unfixed(problem.doms)
is_solved(problem::TNProblem) = count_unfixed(problem) == 0

get_branching_stats(problem::TNProblem) = copy(problem.stats)

reset_problem!(problem::TNProblem) = (reset!(problem.stats); empty!(problem.buffer.branching_cache))
reset_propagated_cache!(problem::TNProblem) = empty!(problem.buffer.branching_cache)