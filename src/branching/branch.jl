# Apply clause assignments to domains
function apply_clause(clause::Clause, variables::Vector{Int}, original_doms::Vector{DomainMask})
    doms = copy(original_doms)
    changed_vars = Int[]

    @inbounds for (var_idx, var_id) in enumerate(variables)
        if ismasked(clause, var_idx)
            new_domain = getbit(clause, var_idx) ? DM_1 : DM_0
            if doms[var_id] != new_domain
                doms[var_id] = new_domain
                push!(changed_vars, var_id)
            end
        end
    end
    return doms, changed_vars
end
function apply_branch!(problem::TNProblem, clause::OptimalBranchingCore.Clause, variables::Vector{Int})
    doms, changed_vars = apply_clause(clause, variables, problem.doms)
    isempty(changed_vars) && (problem.propagated_cache[clause] = doms; return doms)
    touched_tensors = unique(vcat([problem.static.v2t[v] for v in changed_vars]...))
    propagated_doms, _ = propagate(problem.static, doms, touched_tensors)
    @assert !has_contradiction(propagated_doms) "Contradiction found when applying clause $clause"
    
    problem.propagated_cache[clause] = propagated_doms
    return propagated_doms
end

function OptimalBranchingCore.size_reduction(p::TNProblem{INT}, m::AbstractMeasure, cl::Clause{INT}, variables::Vector{Int}) where {INT}
    newdoms = haskey(p.propagated_cache, cl) ? p.propagated_cache[cl] : apply_branch!(p, cl, variables)
    r = measure(p, m) - measure(TNProblem(p.static, newdoms, INT), m)
    return r
end

# Main branch-and-reduce algorithm
function bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer)
    cache = init_cache(problem, config.table_solver, config.measure, config.set_cover_solver, config.selector)
    return _bbsat!(problem, config, reducer, cache)
end

# const tmp_measure = Int[]
# const tmp_count_unfixed = Int[]
# const tmp_count_unfixed_tensors = Int[]

# reset_temp!() = (empty!(tmp_measure); empty!(tmp_count_unfixed); empty!(tmp_count_unfixed_tensors))

function _bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer, region_cache::RegionCache)
    stats = problem.stats
    # println("================================================")
    is_solved(problem) && return Result(true, problem.doms, copy(stats))

    subproblems = findbest(region_cache, problem, config.measure, config.set_cover_solver, config.selector)
    isempty(subproblems) && return Result(false, DomainMask[], copy(stats))
    record_branch!(stats, length(subproblems))
    @inbounds for (i, subproblem_doms) in enumerate(subproblems)
        subproblem = TNProblem(problem.static, subproblem_doms, problem.stats, Dict{Clause{UInt64}, Vector{DomainMask}}())
        # push!(tmp_measure, measure(subproblem, NumHardTensors()))
        # push!(tmp_count_unfixed_tensors, measure(subproblem, NumUnfixedTensors()))
        # push!(tmp_count_unfixed, count_unfixed(subproblem.doms))
        # @show measure(subproblem, NumHardTensors())
        # @show count_unfixed(subproblem.doms)
        result = _bbsat!(subproblem, config, reducer, region_cache)
        result.found && return result
    end
    return Result(false, DomainMask[], copy(stats))
end