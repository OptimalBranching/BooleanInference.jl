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
    @show length(unfixed_vars)
    
    # If no unfixed variables, return empty
    isempty(unfixed_vars) && return Int[]
    
    # find the variable with the least show in each tensor
    # least_show_var = argmin(length(problem.static.v2t[u]) for u in unfixed_vars)
    lens = [length(problem.static.v2t[u]) for u in unfixed_vars]
    minlen = minimum(lens)

    candidates = [u for (u, l) in zip(unfixed_vars, lens) if l == minlen]

    least_show_var = rand(candidates)

    # Compute k-neighboring region
    region = k_neighboring(
        problem.static,
        problem.ws,
        Int32(least_show_var);
        max_tensors = selector.max_tensors,
        k = selector.k
    )
    
    # Explicitly cache the region for branching_table to use
    cache_region!(problem, region)
    
    # Return all variables in the region (boundary first, then inner)
    all_vars = vcat([v.id for v in region.boundary_vars], 
                    [v.id for v in region.inner_vars])
    
    return all_vars
end

