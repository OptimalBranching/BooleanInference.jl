function OptimalBranchingCore.branch_and_reduce(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
    reducer::OptimalBranchingCore.AbstractReducer,
    result_type::Type{TR};
    show_progress::Bool=false,
    tag::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[]
) where TR
    # Step 1: Check if problem is solved (all variables fixed)
    if is_solved(problem)
        @debug "problem is solved"
        cache_branch_solution!(problem)
        return one(result_type)
    end
        
    # Step 2: Try to reduce the problem
    @assert reducer isa NoReducer
    # reduced_problem, reduced_value = reduce_problem(result_type, problem, reducer)
    # if reduced_problem !== problem
    #     # Problem was reduced, recurse on reduced problem
    #     return branch_and_reduce(
    #         reduced_problem, config, reducer, result_type;
    #         tag=tag, show_progress=show_progress
    #     ) * reduced_value
    # end
    
    # Step 3: Select variables for branching
    variables = OptimalBranchingCore.select_variables(
        problem, 
        config.measure, 
        config.selector
    )
    
    # Step 4: Compute branching table
    tbl = OptimalBranchingCore.branching_table(problem, config.table_solver, variables)
    # Step 5: Compute optimal branching rule
    result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, config.measure, config.set_cover_solver)

    # @show result.γ
    
    # Step 6: Branch and recurse
    clauses = OptimalBranchingCore.get_clauses(result)
    @debug "A new branch-level search starts with $(length(clauses)) clauses: $(clauses)"
    
    return sum(enumerate(clauses)) do (i, branch)
        show_progress && (OptimalBranchingCore.print_sequence(stdout, tag); println(stdout))
        @debug "branch=$branch, n_unfixed=$(problem.n_unfixed)"
        
        # Apply branch to get subproblem
        subproblem, local_value = OptimalBranchingCore.apply_branch(problem, branch, variables)
        
        @debug "local_value=$local_value, n_unfixed=$(subproblem.n_unfixed)"
        
        # If branch led to contradiction (UNSAT), skip this branch
        if local_value == 0 || subproblem.n_unfixed == 0 && any(dm -> dm.bits == 0x00, subproblem.doms)
            @debug "Returning zero: local_value=$local_value, n_unfixed=$(subproblem.n_unfixed), has_contradiction=$(any(dm -> dm.bits == 0x00, subproblem.doms))"
            return zero(result_type)
        end
        
        # Recursively solve subproblem
        new_tag = show_progress ? [tag..., (i, length(clauses))] : tag
        sub_result = OptimalBranchingCore.branch_and_reduce(subproblem, config, reducer, result_type;tag=new_tag, show_progress=show_progress)
        
        # Combine results
        sub_result * result_type(local_value)
    end
end

function OptimalBranchingCore.optimal_branching_rule(
    tbl::OptimalBranchingCore.BranchingTable,
    variables::Vector{T},
    problem::TNProblem,
    measure::OptimalBranchingCore.AbstractMeasure,
    solver::OptimalBranchingCore.AbstractSetCoverSolver
) where T
    candidates = OptimalBranchingCore.bit_clauses(tbl)
    return OptimalBranchingCore.greedymerge(candidates, problem, variables, measure)
end


function OptimalBranchingCore.apply_branch(
    problem::TNProblem, 
    clause::OptimalBranchingCore.Clause{INT}, 
    variables::Vector{Int}
) where {INT<:Integer}
    # Copy domain masks
    new_doms = copy(problem.doms)
    # Apply clause: fix variables according to mask and values
    n_fixed = 0
    for i in 1:length(variables)
        if OptimalBranchingCore.readbit(clause.mask, i) == 1
            # This variable is fixed by the clause
            var_id = variables[i]
            bit_val = OptimalBranchingCore.readbit(clause.val, i)
            new_val = (bit_val == 1) ? DM_1 : DM_0
            
            if !is_fixed(problem.doms[var_id])
                new_doms[var_id] = new_val
                n_fixed += 1
            end
        end
    end
    
    @debug "apply_branch: Fixed $n_fixed variables"
  
    # Apply propagation (unit propagation)
    propagated_doms = propagate(problem.static, new_doms)
    
    # Check for contradiction (all domains set to 0x00)
    if any(dm -> dm.bits == 0x00, propagated_doms)
        # UNSAT: contradiction detected during propagation
        @debug "apply_branch: Contradiction detected during propagation"
        return (TNProblem(problem.static, fill(DomainMask(0x00), length(propagated_doms)), 0, problem.ws), 0)
    end
    
    # Count unfixed variables
    new_n_unfixed = count_unfixed(propagated_doms)
    
    @debug "apply_branch: n_unfixed: $(problem.n_unfixed) -> $new_n_unfixed"
    
    # Safety check: problem must have gotten smaller OR we fixed at least one variable
    if new_n_unfixed == problem.n_unfixed && n_fixed == 0
        @debug "apply_branch: No progress made (n_unfixed same and n_fixed=0)"
        return (TNProblem(problem.static, fill(DomainMask(0x00), length(propagated_doms)), 0, problem.ws), 0)
    end

    # Create new problem with updated domains
    new_problem = TNProblem(problem.static, propagated_doms, new_n_unfixed, problem.ws)
    clear_region_cache!(problem)
    return (new_problem, 1)  # local_value = 1 (no scoring for now)
end

function OptimalBranchingCore.reduce_problem(::Type{T}, problem::TNProblem, ::OptimalBranchingCore.NoReducer) where T
    # No reduction - return problem unchanged
    return (problem, one(T))
end

# function reduce_problem(::Type{T}, problem::TNProblem, reducer::UnitPropagationReducer) where T
#     propagated = propagate(problem.static, problem.doms)

#     doms = problem.doms
#     changed = false
#     n_unfixed::Int = 0

#     @inbounds for i in eachindex(doms)
#         dm_new = propagated[i]
#         bits = dm_new.bits

#         if bits == 0x00
#             clear_region_cache!(problem)
#             return (TNProblem(problem.static, propagated, 0, problem.ws), zero(T))
#         end

#         changed |= bits != doms[i].bits
#         n_unfixed += is_fixed(dm_new) ? 0 : 1
#     end

#     if !changed
#         return (problem, one(T))
#     end

#     clear_region_cache!(problem)
#     return (TNProblem(problem.static, propagated, n_unfixed, problem.ws), one(T))
# end
