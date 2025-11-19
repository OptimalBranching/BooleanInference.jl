struct MostOccurrenceSelector <: AbstractSelector end
struct LeastOccurrenceSelector <: AbstractSelector end

function OptimalBranchingCore.select_variables(problem::TNProblem, ::AbstractMeasure, ::MostOccurrenceSelector)
    unfixed_vars = get_unfixed_vars(problem)
    
    isempty(unfixed_vars) && return Int[]
    most_show_var_idx = argmax(length(problem.static.v2t[u]) for u in unfixed_vars)
    return unfixed_vars[most_show_var_idx]
end

function OptimalBranchingCore.select_variables(problem::TNProblem, ::AbstractMeasure, ::LeastOccurrenceSelector)
    unfixed_vars = get_unfixed_vars(problem)
    isempty(unfixed_vars) && return Int[]
    least_show_var_idx = argmin(length(problem.static.v2t[u]) for u in unfixed_vars)
    return unfixed_vars[least_show_var_idx]
end

struct MinGammaSelector <: AbstractSelector
    table_solver::AbstractTableSolver
    set_cover_solver::OptimalBranchingCore.AbstractSetCoverSolver
end

# Constructor will be defined after TNContractionSolver is available
function OptimalBranchingCore.select_variables(problem::TNProblem, measure::AbstractMeasure, selector::MinGammaSelector)
    unfixed_vars = get_unfixed_vars(problem)
    isempty(unfixed_vars) && return Int[]

    best_var = unfixed_vars[1]
    best_gamma = Inf

    @debug "Selecting variables with MinGammaSelector, n_unfixed=$(length(unfixed_vars))"
    # println("Selecting variables with MinGammaSelector, n_unfixed=$(length(unfixed_vars))")
    # Iterate through all unfixed variables
    for var in unfixed_vars
        # Compute branching table for this variable
        tbl, variables = OptimalBranchingCore.branching_table(problem, selector.table_solver, var)
        @debug "tbl: $(tbl)"
        # Skip if table is empty (UNSAT)
        isempty(tbl.table) && continue

        # Compute optimal branching rule for this variable
        result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, measure, selector.set_cover_solver)

        @debug "Optimal branching rule for variable $var: $(OptimalBranchingCore.get_clauses(result))"
        # println("Optimal branching rule for variable $var: $(OptimalBranchingCore.get_clauses(result))")

        # Get the gamma value
        gamma = result.γ
        @debug "Gamma for variable $var: $gamma"
        # println("Gamma for variable $var: $gamma")

        # Update best variable if this gamma is smaller
        if gamma < best_gamma
            @debug "Updating best variable to $var with gamma $gamma"
            # println("Updating best variable to $var with gamma $gamma")
            best_gamma = gamma
            best_var = var
        end
    end
    return best_var
end

# struct LocalTensorSelector <: AbstractSelector end

# function OptimalBranchingCore.select_variables(problem::TNProblem, ::AbstractMeasure, ::LocalTensorSelector)
#     # Select tensor with the most unfixed variables (and has more than 1 unfixed variables)
#     best_tensor_id = nothing
#     max_unfixed = 0
    
#     for (tensor_id, tensor) in enumerate(problem.static.tensors)
#         # Get the variables for this tensor
#         tensor_vars = tensor.var_axes
        
#         # Partition variables into fixed and unfixed
#         fixed_positions, unfixed_positions, unfixed_var_ids = partition_tensor_variables(tensor_vars, problem.doms)
        
#         n_unfixed = length(unfixed_var_ids)
        
#         # Update best tensor if this one has more unfixed variables
#         # Only consider tensors with more than 1 unfixed variable
#         if n_unfixed > 1 && n_unfixed > max_unfixed
#             max_unfixed = n_unfixed
#             best_tensor_id = tensor_id
#         end
#     end
    
#     if best_tensor_id !== nothing
#         @debug "Selecting tensor $(best_tensor_id) with $max_unfixed unfixed variables"
#         return best_tensor_id
#     end
    
#     # If no tensor satisfies the conditions, return empty array
#     return Int[]
# end