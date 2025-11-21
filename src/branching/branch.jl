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
    haskey(problem.propagated_cache, clause) && return problem.propagated_cache[clause]

    # Cache miss: compute from scratch
    doms, changed_vars = apply_clause(clause, variables, problem.doms)
    propagated_doms = propagate(problem.static, doms, changed_vars)

    @assert !has_contradiction(propagated_doms) "Contradiction found when applying clause $clause"
    # Cache the result for future use
    problem.propagated_cache[clause] = propagated_doms
    return propagated_doms
end

function OptimalBranchingCore.size_reduction(p::TNProblem, m::AbstractMeasure, cl::Clause{INT}, variables::Vector{Int}) where {INT}
    new_doms = apply_branch!(p, cl, variables)
    return measure(p, m) - measure(TNProblem(p.static, new_doms), m)
end

# Main branch-and-reduce algorithm
function OptimalBranchingCore.branch_and_reduce(problem::TNProblem, config::OptimalBranchingCore.BranchingStrategy, reducer::OptimalBranchingCore.AbstractReducer, result_type::Type{TR}; show_progress::Bool=false, tag::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[]) where TR
    stats = problem.stats
    current_depth = length(tag)

    if is_solved(problem)
        record_solved_leaf!(stats, current_depth)
        return one(result_type)
    end

    record_depth!(stats, current_depth)

    # Select region for branching
    region = select_region(problem, config.measure, config.selector)

    # Compute branching table
    tbl, variables = branching_table!(problem, config.table_solver, region)

    # Check if table is empty (UNSAT)
    if isempty(tbl.table)
        record_unsat_leaf!(stats, current_depth)
        return zero(result_type)
    end

    # Compute optimal branching rule
    result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, config.measure, config.set_cover_solver)

    # Branch and recurse
    clauses = OptimalBranchingCore.get_clauses(result)
    record_branch!(stats, length(clauses), current_depth)

    accum = zero(result_type)
    for (i, clause) in enumerate(clauses)
        show_progress && (OptimalBranchingCore.print_sequence(stdout, tag); println(stdout))

        # Read the propagated domains from the cache
        propagated_doms = problem.propagated_cache[clause]
        
        if count_unfixed(propagated_doms) == 0
            record_solved_leaf!(stats, current_depth)
            @show problem.stats
            return one(result_type)
        end

        subproblem = TNProblem(problem.static, propagated_doms, problem.stats)

        # Recursively solve subproblem
        push!(tag, (i, length(clauses)))
        sub_result = OptimalBranchingCore.branch_and_reduce(subproblem, config, reducer, result_type; tag, show_progress)
        pop!(tag)

        # Combine results
        accum = accum + sub_result

        # Early exit if found solution
        if accum > zero(result_type)
            return accum
        end
    end

    return accum
end
