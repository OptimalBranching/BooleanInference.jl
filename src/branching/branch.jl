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

# Apply a clause to domains and propagate (internal helper)
function apply_branch!(problem::TNProblem, clause::OptimalBranchingCore.Clause, variables::Vector{Int})
    # Try to use cached propagated domains
    haskey(problem.propagated_cache, clause) && (return problem.propagated_cache[clause])

    # Cache miss: compute from scratch
    doms, changed_vars = apply_clause(clause, variables, problem.doms)
    propagated_doms = propagate(problem.static, doms, changed_vars)

    @assert !has_contradiction(propagated_doms) "Contradiction found when applying clause $clause"
    # Cache the result for future use
    problem.propagated_cache[clause] = propagated_doms
    return propagated_doms
end

function OptimalBranchingCore.size_reduction(p::TNProblem{INT}, m::AbstractMeasure, cl::Clause{INT}, variables::Vector{Int}) where {INT}
    new_doms = apply_branch!(p, cl, variables)
    return measure(p, m) - measure(TNProblem(p.static, new_doms, INT), m)
end

# Main branch-and-reduce algorithm
function branch_and_reduce!(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer, result_type::Type{TR}; show_progress::Bool=false, tag::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[]) where TR
    stats = problem.stats
    empty!(problem.propagated_cache)

    is_solved(problem) && return result_type(true, problem.doms, copy(stats))
    region = select_region(problem, config.measure, config.selector)

    tbl, variables = branching_table!(problem, config.table_solver, region)
    isempty(tbl.table) && return result_type(false, nothing, copy(stats))

    result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, config.measure, config.set_cover_solver)
    clauses = OptimalBranchingCore.get_clauses(result)
    record_branch!(stats, length(clauses))

    accum = result_type(false, nothing, copy(stats))
    @inbounds for (i, clause) in enumerate(clauses)
        show_progress && (OptimalBranchingCore.print_sequence(stdout, tag); println(stdout))
        propagated_doms = problem.propagated_cache[clause]

        subproblem = TNProblem(problem.static, propagated_doms, problem.stats, Dict{Clause{UInt64}, Vector{DomainMask}}())
        push!(tag, (i, length(clauses)))
        sub_result = branch_and_reduce!(subproblem, config, reducer, result_type; tag, show_progress)
        pop!(tag)

        accum = accum + sub_result
        accum.found && return accum
    end
    return accum
end
