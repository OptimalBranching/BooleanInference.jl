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

struct TNProblem{INT<:Integer} <: AbstractProblem
    static::BipartiteGraph   # TODO: simplify the graph type
    doms::Vector{DomainMask}
    stats::BranchingStats
    propagated_cache::Dict{Clause{INT}, Vector{DomainMask}}

    function TNProblem{INT}(static::BipartiteGraph, doms::Vector{DomainMask}, stats::BranchingStats=BranchingStats(), propagated_cache::Dict{Clause{INT}, Vector{DomainMask}}=Dict{Clause{INT}, Vector{DomainMask}}()) where {INT<:Integer}
        new{INT}(static, doms, stats, propagated_cache)
    end
end

function TNProblem(static::BipartiteGraph, ::Type{INT}=UInt64) where {INT<:Integer}
    doms, _ = propagate(static, init_doms(static), collect(1:length(static.tensors)))
    has_contradiction(doms) && error("Domain has contradiction")
    return TNProblem{INT}(static, doms)
end

# TODO: Reduce the number of interfaces
# Constructor with explicit domains
function TNProblem(static::BipartiteGraph, doms::Vector{DomainMask}, ::Type{INT}=UInt64) where {INT<:Integer}
    return TNProblem{INT}(static, doms)
end

# Constructor with all parameters (for internal use)
function TNProblem(static::BipartiteGraph, doms::Vector{DomainMask}, stats::BranchingStats, propagated_cache::Dict{Clause{INT}, Vector{DomainMask}}) where {INT<:Integer}
    return TNProblem{INT}(static, doms, stats, propagated_cache)
end

function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(count_unfixed(problem))/$(length(problem.static.vars)))")
end

# Custom show for propagated_cache: only display keys
function Base.show(io::IO, cache::Dict{Clause{INT}, Vector{DomainMask}}) where {INT<:Integer}
    print(io, "Dict{Clause{", INT, "}, Vector{DomainMask}} with keys: ")
    print(io, collect(keys(cache)))
end

get_var_value(problem::TNProblem, var_id::Int) = get_var_value(problem.doms, var_id)
get_var_value(problem::TNProblem, var_ids::Vector{Int}) = Bool[get_var_value(problem.doms, var_id) for var_id in var_ids]

count_unfixed(problem::TNProblem) = count_unfixed(problem.doms)
is_solved(problem::TNProblem) = count_unfixed(problem) == 0

get_branching_stats(problem::TNProblem) = copy(problem.stats)

reset_problem!(problem::TNProblem) = (reset!(problem.stats); empty!(problem.propagated_cache))
reset_propagated_cache!(problem::TNProblem) = empty!(problem.propagated_cache)