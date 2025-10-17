# Selector implementations for TNProblem
struct LeastOccurrenceSelector <: AbstractSelector
    k::Int  # number of hops
    max_tensors::Int
end

LeastOccurrenceSelector(k::Int) = LeastOccurrenceSelector(k, 10)

function OptimalBranchingCore.select_variables(
    problem::TNProblem, 
    measure::AbstractMeasure, 
    selector::LeastOccurrenceSelector
)
    # Find unfixed variables
    unfixed_vars = get_unfixed_vars(problem.doms)
    
    # If no unfixed variables, return empty
    isempty(unfixed_vars) && return Int[]
    
    # find the variable with the least show in each tensor
    least_show_var_idx = argmin(length(problem.static.v2t[u]) for u in unfixed_vars)
    
    # Compute k-neighboring region (only expanding to unfixed variables)
    # The returned region will only contain unfixed variables
    region = k_neighboring(
        problem.static,
        problem.ws,
        problem.doms,
        unfixed_vars[least_show_var_idx];
        max_tensors = selector.max_tensors,
        k = selector.k
    )
    
    # Cache the region for branching_table to use
    cache_region!(problem, region)
    
    # Return all variables in the region (boundary first, then inner)
    # These are guaranteed to be unfixed since k_neighboring filters them
    return vcat(region.boundary_vars, region.inner_vars)
end

