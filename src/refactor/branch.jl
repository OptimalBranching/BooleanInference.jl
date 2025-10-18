struct BranchingCandidate
    focus_var::Int
    region::Union{Nothing,Region}
    variables::Vector{Int}
    table::OptimalBranchingCore.BranchingTable
    result::OptimalBranchingCore.OptimalBranchingResult
    signature::Vector{UInt8}
end

mutable struct GammaQueueState
    queue::PriorityQueue{Int,Float64}
    candidates::Dict{Int,BranchingCandidate}
end
GammaQueueState() = GammaQueueState(PriorityQueue{Int,Float64}(), Dict{Int,BranchingCandidate}())

@inline function gamma_queue_state(problem::TNProblem)
    ws = problem.ws
    state = ws.branch_queue
    if state === nothing
        state = GammaQueueState()
        ws.branch_queue = state
    end
    return state::GammaQueueState
end

@inline function dom_signature(problem::TNProblem, vars::Vector{Int})
    sig = Vector{UInt8}(undef, length(vars))
    @inbounds for (i, var_id) in enumerate(vars)
        sig[i] = problem.doms[var_id].bits
    end
    return sig
end

@inline function candidate_valid(candidate::BranchingCandidate, problem::TNProblem)::Bool
    vars = candidate.variables
    sig = candidate.signature
    length(vars) == length(sig) || return false
    @inbounds for (i, var_id) in enumerate(vars)
        dm = problem.doms[var_id]
        if dm.bits == 0x00 || dm.bits != sig[i]
            return false
        end
    end
    return true
end

function build_region_for_variable(
    problem::TNProblem,
    selector::LeastOccurrenceSelector,
    var_id::Int,
)
    is_fixed(problem.doms[var_id]) && return nothing
    return k_neighboring(
        problem.static,
        problem.doms,
        var_id;
        max_tensors = selector.max_tensors,
        k = selector.k,
    )
end

function compute_branching_candidate_for_var(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
    selector::LeastOccurrenceSelector,
    var_id::Int,
)
    region = build_region_for_variable(problem, selector, var_id)
    region === nothing && return nothing
    cache_region!(problem, region)
    variables = vcat(region.boundary_vars, region.inner_vars)
    isempty(variables) && return nothing
    tbl = OptimalBranchingCore.branching_table(problem, config.table_solver, variables)
    result = OptimalBranchingCore.optimal_branching_rule(
        tbl,
        variables,
        problem,
        config.measure,
        config.set_cover_solver,
    )
    @debug "candidate_gamma" focus=region.id γ=result.γ
    signature = dom_signature(problem, variables)
    return BranchingCandidate(region.id, region, variables, tbl, result, signature)
end

function default_branching_candidate(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
)
    variables = OptimalBranchingCore.select_variables(
        problem,
        config.measure,
        config.selector,
    )
    tbl = OptimalBranchingCore.branching_table(problem, config.table_solver, variables)
    result = OptimalBranchingCore.optimal_branching_rule(
        tbl,
        variables,
        problem,
        config.measure,
        config.set_cover_solver,
    )
    region = get_cached_region(problem)
    if region !== nothing
        set_last_region!(problem, region.id)
    end
    focus_var = region === nothing ? (isempty(variables) ? 0 : variables[1]) : region.id
    signature = dom_signature(problem, variables)
    return BranchingCandidate(focus_var, region, variables, tbl, result, signature)
end

function ensure_candidate!(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
    selector::LeastOccurrenceSelector,
    state::GammaQueueState,
    var_id::Int,
)
    candidate = get(state.candidates, var_id, nothing)
    if candidate !== nothing && candidate_valid(candidate, problem)
        return candidate
    end

    candidate = compute_branching_candidate_for_var(problem, config, selector, var_id)
    if candidate === nothing
        if haskey(state.queue, var_id)
            delete!(state.queue, var_id)
        end
        delete!(state.candidates, var_id)
        return nothing
    end

    state.candidates[var_id] = candidate
    state.queue[var_id] = candidate.result.γ
    return candidate
end

function prune_fixed!(state::GammaQueueState, problem::TNProblem)
    to_remove = Int[]
    for var_id in keys(state.candidates)
        if is_fixed(problem.doms[var_id])
            push!(to_remove, var_id)
        end
    end
    for var_id in to_remove
        delete!(state.candidates, var_id)
        if haskey(state.queue, var_id)
            delete!(state.queue, var_id)
        end
    end
    return nothing
end

function populate_queue!(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
    selector::LeastOccurrenceSelector,
    state::GammaQueueState,
)
    for var_id in get_unfixed_vars(problem.doms)
        haskey(state.candidates, var_id) && continue
        ensure_candidate!(problem, config, selector, state, var_id)
    end
    return nothing
end

function select_branching_candidate(
    problem::TNProblem,
    config::OptimalBranchingCore.BranchingStrategy,
)
    selector = config.selector
    selector isa LeastOccurrenceSelector || return default_branching_candidate(problem, config)

    state = gamma_queue_state(problem)
    prune_fixed!(state, problem)
    isempty(state.queue) && populate_queue!(problem, config, selector, state)

    while !isempty(state.queue)
        focus_var, _ = peek(state.queue)
        candidate = ensure_candidate!(problem, config, selector, state, focus_var)
        candidate === nothing && continue

        if !candidate_valid(candidate, problem)
            # invalid candidate was recomputed but still invalid (e.g., empty region)
            delete!(state.queue, focus_var)
            delete!(state.candidates, focus_var)
            continue
        end

        region = candidate.region
        if region !== nothing
            set_last_region!(problem, region.id)
        end
        return candidate
    end

    return default_branching_candidate(problem, config)
end

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
    
    # Step 3-5: Evaluate branching candidates and select the best one using γ
    candidate = select_branching_candidate(problem, config)
    variables = candidate.variables
    tbl = candidate.table
    result = candidate.result
    @debug "selected_gamma" focus=(candidate.region === nothing ? nothing : candidate.region.id) γ=result.γ
    
    # Step 6: Branch and recurse
    clauses = OptimalBranchingCore.get_clauses(result)
    @debug "A new branch-level search starts with $(length(clauses)) clauses: $(clauses)"
    
    return sum(enumerate(clauses)) do (i, branch)
        show_progress && (OptimalBranchingCore.print_sequence(stdout, tag); println(stdout))
        @debug "branch=$branch, n_unfixed=$(problem.n_unfixed)"
        
        # Apply branch to get subproblem
        subproblem, local_value = OptimalBranchingCore.apply_branch(
            problem, 
            branch, 
            variables
        )
        
        @debug "local_value=$local_value, n_unfixed=$(subproblem.n_unfixed)"
        
        # If branch led to contradiction (UNSAT), skip this branch
        if local_value == 0 || subproblem.n_unfixed == 0 && any(dm -> dm.bits == 0x00, subproblem.doms)
            @debug "Returning zero: local_value=$local_value, n_unfixed=$(subproblem.n_unfixed), has_contradiction=$(any(dm -> dm.bits == 0x00, subproblem.doms))"
            return zero(result_type)
        end
        
        # Recursively solve subproblem
        new_tag = show_progress ? [tag..., (i, length(clauses))] : tag
        sub_result = OptimalBranchingCore.branch_and_reduce(
            subproblem, 
            config, 
            reducer, 
            result_type;
            tag=new_tag,
            show_progress=show_progress
        )
        
        # Combine results
        sub_result * result_type(local_value)
    end
end

# function OptimalBranchingCore.optimal_branching_rule(
#     tbl::OptimalBranchingCore.BranchingTable,
#     variables::Vector{T},
#     problem::TNProblem,
#     measure::OptimalBranchingCore.AbstractMeasure,
#     solver::OptimalBranchingCore.AbstractSetCoverSolver
# ) where T
#     candidates = OptimalBranchingCore.bit_clauses(tbl)
#     return OptimalBranchingCore.greedymerge(candidates, problem, variables, measure)
# end


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
    
    # Safety check: must fix at least one variable to make progress
    # @assert n_fixed > 0 "Branch clause must fix at least one variable to avoid infinite loop"

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
    if new_n_unfixed > problem.n_unfixed
        @debug "apply_branch: ERROR - unfixed count increased!"
        return (TNProblem(problem.static, fill(DomainMask(0x00), length(propagated_doms)), 0, problem.ws), 0)
    elseif new_n_unfixed == problem.n_unfixed && n_fixed == 0
        @debug "apply_branch: No progress made (n_unfixed same and n_fixed=0)"
        return (TNProblem(problem.static, fill(DomainMask(0x00), length(propagated_doms)), 0, problem.ws), 0)
    end

    # Create new problem with updated domains
    new_problem = TNProblem(
        problem.static,
        propagated_doms,
        new_n_unfixed,
        problem.ws  # Reuse workspace (thread-local)
    )
    
    clear_region_cache!(problem)
    
    return (new_problem, 1)  # local_value = 1 (no scoring for now)
end

function OptimalBranchingCore.reduce_problem(
    ::Type{T},
    problem::TNProblem,
    ::OptimalBranchingCore.NoReducer
) where T
    # No reduction - return problem unchanged
    return (problem, one(T))
end

# TODO: Implement other reducers
# function reduce_problem(::Type{T}, problem::TNProblem, reducer::UnitPropagationReducer) where T
#     # Apply unit propagation
#     new_doms, propagated = unit_propagate(problem.static, problem.doms)
#     if propagated
#         new_n_unfixed = count_unfixed(new_doms)
#         new_problem = TNProblem(problem.static, new_doms, new_n_unfixed, problem.ws)
#         return (new_problem, one(T))
#     else
#         return (problem, one(T))
#     end
# end
