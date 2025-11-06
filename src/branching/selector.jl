struct MostOccurrenceSelector <: AbstractSelector end

function OptimalBranchingCore.select_variables(
    problem::TNProblem,
    measure::AbstractMeasure,
    selector::MostOccurrenceSelector
)
    unfixed_vars = get_unfixed_vars(problem.doms)
    isempty(unfixed_vars) && return Int[]
    least_show_var_idx = argmax(length(problem.static.v2t[u]) for u in unfixed_vars)

    return unfixed_vars[least_show_var_idx]
end

"""
    MinGammaSelector <: AbstractSelector

Selector that chooses the variable with minimum branching gamma.
For each unfixed variable, it computes the branching gamma on the corresponding
region and selects the variable with the smallest gamma value.

This selector does not consider performance optimization and will iterate through
all unfixed variables to find the best one.
"""
struct MinGammaSelector <: AbstractSelector
    table_solver::AbstractTableSolver
    set_cover_solver::OptimalBranchingCore.AbstractSetCoverSolver
end

# Constructor will be defined after TNContractionSolver is available

function OptimalBranchingCore.select_variables(
    problem::TNProblem,
    measure::AbstractMeasure,
    selector::MinGammaSelector
)
    unfixed_vars = get_unfixed_vars(problem.doms)
    isempty(unfixed_vars) && return Int[]

    best_var = unfixed_vars[1]
    best_gamma = Inf

    @debug "Selecting variables with MinGammaSelector, n_unfixed=$(length(unfixed_vars))"
    # println("Selecting variables with MinGammaSelector, n_unfixed=$(length(unfixed_vars))")
    # Iterate through all unfixed variables
    for var in unfixed_vars
        # Compute branching table for this variable
        tbl, variables = OptimalBranchingCore.branching_table(
            problem,
            selector.table_solver,
            var
        )
        # @show tbl
        # Skip if table is empty (UNSAT)
        if isempty(tbl.table)
            continue
        end

        # Compute optimal branching rule for this variable
        result = OptimalBranchingCore.optimal_branching_rule(
            tbl,
            variables,
            problem,
            measure,
            selector.set_cover_solver
        )

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

