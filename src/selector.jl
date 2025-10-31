struct LeastOccurrenceSelector <: AbstractSelector end

function OptimalBranchingCore.select_variables(
    problem::TNProblem, 
    measure::AbstractMeasure, 
    selector::LeastOccurrenceSelector
)
    unfixed_vars = get_unfixed_vars(problem.doms)
    isempty(unfixed_vars) && return Int[]
    least_show_var_idx = argmin(length(problem.static.v2t[u]) for u in unfixed_vars)

    return unfixed_vars[least_show_var_idx]

#     # if cached region is not empty, return it
#     cached_region = get_cached_region(unfixed_vars[least_show_var_idx])
#     if !isnothing(cached_region)
#         return vcat(cached_region.boundary_vars, cached_region.inner_vars)
#     end
    
#     # Compute k-neighboring region (only expanding to unfixed variables)
#     # The returned region will only contain unfixed variables
#     region = k_neighboring(
#         problem.static,
#         problem.doms,
#         unfixed_vars[least_show_var_idx];
#         max_tensors = selector.max_tensors,
#         k = selector.k
#     )
#     cache_region!(region)
    
#     # Return all variables in the region (boundary first, then inner)
#     # These are guaranteed to be unfixed since k_neighboring filters them
#     return vcat(region.boundary_vars, region.inner_vars)
end

