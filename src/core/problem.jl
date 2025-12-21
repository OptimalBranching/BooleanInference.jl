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

struct Assignment
    var_id::Int
    value::DomainMask
    reason_tensor::Int
    level::Int
end

function Base.show(io::IO, a::Assignment)
    if a.reason_tensor == 0
        print(io, "x$(a.var_id)@$(a.level) ← $(a.value) (direct decision)")
    else
        print(io, "x$(a.var_id)@$(a.level) ← $(a.value) (reason: tensor $(a.reason_tensor))")
    end
end

mutable struct PropagateReason
    reason_tensor_id::Int
    mask0::UInt16
    mask1::UInt16
end

struct SolverBuffer
    touched_tensors::Vector{Int}  # Tensors that need propagation
    in_queue::BitVector           # Track which tensors are queued for processing
    scratch_doms::Vector{DomainMask}  # Temporary domain storage for propagation
    branching_cache::Dict{Clause{UInt64}, Float64}  # Cache measure values for branching configurations
    activity_scores::Vector{Float64}
    connection_scores::Vector{Float64}

    trail::Vector{Assignment}
    trail_lim::Vector{Int}

end

function SolverBuffer(cn::ConstraintNetwork)
    n_tensors = length(cn.tensors)
    n_vars = length(cn.vars)
    SolverBuffer(
        sizehint!(Int[], n_tensors),
        falses(n_tensors),
        Vector{DomainMask}(undef, n_vars),
        Dict{Clause{UInt64}, Float64}(),
        zeros(Float64, n_vars),
        zeros(Float64, n_vars),
        sizehint!(Assignment[], n_vars), Int[]
    )
end

struct TNProblem <: AbstractProblem
    static::ConstraintNetwork
    doms::Vector{DomainMask}
    stats::BranchingStats
    buffer::SolverBuffer

    # Internal constructor: final constructor that creates the instance
    function TNProblem(static::ConstraintNetwork, doms::Vector{DomainMask}, stats::BranchingStats, buffer::SolverBuffer)
        new(static, doms, stats, buffer)
    end
end

# Initialize domains with propagation
function initialize(static::ConstraintNetwork, buffer::SolverBuffer)
    doms = propagate(static, init_doms(static), collect(1:length(static.tensors)), buffer)
    has_contradiction(doms) && error("Domain has contradiction")
    @inbounds for var_id in 1:length(static.vars)
        isempty(static.v2t[var_id]) && (doms[var_id] = DM_0)
    end
    return doms
end

# Constructor: Initialize from ConstraintNetwork with optional explicit domains
function TNProblem(static::ConstraintNetwork, doms::Union{Vector{DomainMask}, Nothing}=nothing, stats::BranchingStats=BranchingStats())
    buffer = SolverBuffer(static)
    isnothing(doms) && (doms = initialize(static, buffer))
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

reset_stats!(problem::TNProblem) = reset!(problem.stats)
reset_propagated_cache!(problem::TNProblem) = empty!(problem.buffer.branching_cache)
