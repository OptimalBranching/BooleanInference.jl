# Result type for branch-and-reduce solving
struct Result
    found::Bool
    solution::Union{Nothing, Vector{DomainMask}}   # TODO: check the performance, do not allow nothing
    stats::BranchingStats
end

# Interface required by OptimalBranchingCore
Base.one(::Type{Result}) = Result(true, nothing, BranchingStats())
Base.zero(::Type{Result}) = Result(false, nothing, BranchingStats())
Base.:+(a::Result, b::Result) = a.found ? a : b
Base.:>(a::Result, b::Result) = a.found && !b.found

function Base.show(io::IO, r::Result)
    if r.found
        has_sol = !isnothing(r.solution)
        print(io, "Result(found=true, solution=$(has_sol ? "available" : "none"), stats=...)")
    else
        print(io, "Result(found=false, stats=...)")
    end
end

struct TNProblem{INT<:Integer} <: AbstractProblem
    static::BipartiteGraph   # TODO: simplify the graph type
    doms::Vector{DomainMask}
    n_unfixed::Int           # Do not store the number of unfixed variables.
    stats::BranchingStats
    propagated_cache::Dict{Clause{INT}, Vector{DomainMask}}

    function TNProblem{INT}(static::BipartiteGraph, doms::Vector{DomainMask}, stats::BranchingStats=BranchingStats(), propagated_cache::Dict{Clause{INT}, Vector{DomainMask}}=Dict{Clause{INT}, Vector{DomainMask}}()) where {INT<:Integer}
        n_unfixed = count_unfixed(doms)
        new{INT}(static, doms, n_unfixed, stats, propagated_cache)
    end
end

function TNProblem(static::BipartiteGraph, ::Type{INT}=UInt64) where {INT<:Integer}
    doms = propagate(static, init_doms(static))
    has_contradiction(doms) && error("Domain has contradiction")
    return TNProblem{INT}(static, doms)
end

### Reduce the number of interfaces
# Constructor with explicit domains
function TNProblem(static::BipartiteGraph, doms::Vector{DomainMask}, ::Type{INT}=UInt64) where {INT<:Integer}
    return TNProblem{INT}(static, doms)
end

# Constructor with all parameters (for internal use)
function TNProblem(static::BipartiteGraph, doms::Vector{DomainMask}, stats::BranchingStats, propagated_cache::Dict{Clause{INT}, Vector{DomainMask}}) where {INT<:Integer}
    return TNProblem{INT}(static, doms, stats, propagated_cache)
end

function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(problem.n_unfixed)/$(length(problem.static.vars)))")
end

get_var_value(problem::TNProblem, var_id::Int) = get_var_value(problem.doms, var_id)
get_var_value(problem::TNProblem, var_ids::Vector{Int}) = Bool[get_var_value(problem.doms, var_id) for var_id in var_ids]

is_solved(problem::TNProblem) = problem.n_unfixed == 0

get_branching_stats(problem::TNProblem) = copy(problem.stats)

reset_problem!(problem::TNProblem) = (reset!(problem.stats); empty!(problem.propagated_cache))