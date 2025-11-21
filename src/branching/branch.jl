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
    haskey(problem.propagated_cache, clause) && (return problem.propagated_cache[clause])

    doms, changed_vars = apply_clause(clause, variables, problem.doms)
    propagated_doms = propagate(problem.static, doms, changed_vars)

    @assert !has_contradiction(propagated_doms) "Contradiction found when applying clause $clause"
    problem.propagated_cache[clause] = propagated_doms
    return propagated_doms
end

function OptimalBranchingCore.size_reduction(p::TNProblem{INT}, m::AbstractMeasure, cl::Clause{INT}, variables::Vector{Int}) where {INT}
    new_doms = apply_branch!(p, cl, variables)
    return measure(p, m) - measure(TNProblem(p.static, new_doms, INT), m)
end

# Main branch-and-reduce algorithm
function bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer)
    cache = init_cache(problem, config.table_solver, config.measure, config.set_cover_solver)
    return _bbsat!(problem, config, reducer, cache)
end

function _bbsat!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer, region_cache::RegionCache; tag::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[], show_progress::Bool=false)
    stats = problem.stats
    empty!(problem.propagated_cache)

    is_solved(problem) && return Result(true, problem.doms, copy(stats))

    region_vars, result = findbest(region_cache)
    clauses = OptimalBranchingCore.get_clauses(result)
    record_branch!(stats, length(clauses))

    accum = Result(false, nothing, copy(stats))
    @inbounds for (i, clause) in enumerate(clauses)
        propagated_doms = problem.propagated_cache[clause]

        subproblem = TNProblem(problem.static, propagated_doms, problem.stats, Dict{Clause{UInt64}, Vector{DomainMask}}())
        success, new_region_cache = update(region_cache, subproblem, touched_vars(region_vars, clause), config.table_solver, config.measure, config.set_cover_solver)
        success || continue

        push!(tag, (i, length(clauses)))
        sub_result = _bbsat!(subproblem, config, reducer, new_region_cache; tag, show_progress)
        pop!(tag)

        accum = accum + sub_result
        accum.found && return accum
    end
    return accum
end

touched_vars(region_vars::Vector{Int}, clause::OptimalBranchingCore.Clause) = [var for (k, var) in enumerate(region_vars) if readbit(clause.mask, k) == 1]