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
    touched_clauses::Vector{Int}  # ClauseTensors that need propagation
    clause_in_queue::BitVector    # Track which clauses are queued for processing
    scratch_doms::Vector{DomainMask}  # Temporary domain storage for propagation
    branching_cache::Dict{Clause{UInt64},Float64}  # Cache measure values for branching configurations
    connection_scores::Vector{Float64}
end

function SolverBuffer(cn::ConstraintNetwork)
    n_tensors = length(cn.tensors)
    n_vars = length(cn.vars)
    SolverBuffer(
        sizehint!(Int[], n_tensors),
        falses(n_tensors),
        Int[],
        BitVector(),
        Vector{DomainMask}(undef, n_vars),
        Dict{Clause{UInt64},Float64}(),
        zeros(Float64, n_vars)
    )
end

struct TNProblem <: AbstractProblem
    static::ConstraintNetwork
    doms::Vector{DomainMask}
    stats::BranchingStats
    buffer::SolverBuffer
    learned_clauses::Vector{ClauseTensor}
    v2c::Vector{Vector{Int}}

    # Internal constructor: final constructor that creates the instance
    function TNProblem(static::ConstraintNetwork, doms::Vector{DomainMask}, stats::BranchingStats, buffer::SolverBuffer, learned_clauses::Vector{ClauseTensor}, v2c::Vector{Vector{Int}})
        new(static, doms, stats, buffer, learned_clauses, v2c)
    end
end

# Initialize domains with propagation
function initialize(static::ConstraintNetwork, learned_clauses::Vector{ClauseTensor}, v2c::Vector{Vector{Int}}, buffer::SolverBuffer)
    doms = propagate(static, learned_clauses, v2c, init_doms(static), collect(1:length(static.tensors)), collect(1:length(learned_clauses)), buffer)
    has_contradiction(doms) && error("Domain has contradiction")
    return doms
end

# Constructor: Initialize from ConstraintNetwork with optional explicit domains
function TNProblem(
    static::ConstraintNetwork;
    doms::Union{Vector{DomainMask},Nothing}=nothing,
    stats::BranchingStats=BranchingStats(),
    learned_clauses::Vector{ClauseTensor}=ClauseTensor[],
)
    buffer = SolverBuffer(static)
    # Learned clauses are assumed to be in compressed variable space
    length(learned_clauses) > 0 ? v2c = build_clause_v2c(length(static.vars), learned_clauses) : v2c = Vector{Int}[]
    isnothing(doms) && (doms = initialize(static, learned_clauses, v2c, buffer))
    return TNProblem(static, doms, stats, buffer, learned_clauses, v2c)
end

function build_clause_v2c(n_vars::Int, clauses::Vector{ClauseTensor})
    v2c = [Int[] for _ in 1:n_vars]
    @inbounds for (c_idx, clause) in enumerate(clauses)
        for v in clause.vars
            push!(v2c[v], c_idx)
        end
    end
    return v2c
end

function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(count_unfixed(problem))/$(length(problem.static.vars)))")
end

get_var_value(problem::TNProblem, var_id::Int) = get_var_value(problem.doms, var_id)
get_var_value(problem::TNProblem, var_ids::Vector{Int}) = Bool[get_var_value(problem.doms, var_id) for var_id in var_ids]

map_var(problem::TNProblem, orig_var_id::Int) = problem.static.orig_to_new[orig_var_id]
map_vars(problem::TNProblem, orig_var_ids::Vector{Int}) = [map_var(problem, v) for v in orig_var_ids]
function map_vars_checked(problem::TNProblem, orig_var_ids::Vector{Int}, label::AbstractString)
    mapped = map_vars(problem, orig_var_ids)
    any(==(0), mapped) && error("$label variables were eliminated during compression")
    return mapped
end

count_unfixed(problem::TNProblem) = count_unfixed(problem.doms)
is_solved(problem::TNProblem) = count_unfixed(problem) == 0

get_branching_stats(problem::TNProblem) = copy(problem.stats)

reset_stats!(problem::TNProblem) = reset!(problem.stats)
reset_propagated_cache!(problem::TNProblem) = empty!(problem.buffer.branching_cache)
