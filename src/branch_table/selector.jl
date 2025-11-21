function create_region(problem::TNProblem, variable::Int, selector::AbstractSelector)
    return k_neighboring(problem.static, problem.doms, variable; max_tensors = selector.max_tensors, k = selector.k)
end

struct MostOccurrenceSelector <: AbstractSelector 
    k::Int
    max_tensors::Int
end

function select_region(problem::TNProblem, ::AbstractMeasure, selector::MostOccurrenceSelector)
    unfixed_vars = get_unfixed_vars(problem)
    most_show_var_idx = argmax(length(problem.static.v2t[u]) for u in unfixed_vars)
    return create_region(problem, unfixed_vars[most_show_var_idx], selector)
end

struct MinGammaSelector <: AbstractSelector
    k::Int
    max_tensors::Int
    table_solver::AbstractTableSolver
    set_cover_solver::AbstractSetCoverSolver
end

# Constructor will be defined after TNContractionSolver is available
function select_region(problem::TNProblem, measure::AbstractMeasure, selector::MinGammaSelector)
    unfixed_vars = get_unfixed_vars(problem)

    best_region = nothing
    best_gamma = Inf
    gamma_values = Float64[]

    @inbounds for var in unfixed_vars
        region = create_region(problem, var, selector)

        tbl, variables = branching_table!(problem, selector.table_solver, region)
        isempty(tbl.table) && continue

        # Compute optimal branching rule for this variable
        result = OptimalBranchingCore.optimal_branching_rule(tbl, variables, problem, measure, selector.set_cover_solver)

        @debug "Optimal branching rule for variable $var: $(OptimalBranchingCore.get_clauses(result))"

        # Get the gamma value
        push!(gamma_values, result.γ)

        # Update best variable if this gamma is smaller
        if result.γ < best_gamma
            best_gamma = result.γ
            best_region = copy(region)
        end
    end
    @show gamma_values
    @show best_gamma
    @show best_region
    return best_region
end