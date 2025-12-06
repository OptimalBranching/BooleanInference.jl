struct NumUnfixedVars <: AbstractMeasure end
function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedVars)
    return count_unfixed(problem.doms)
end

struct NumUnfixedTensors <: AbstractMeasure end
function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedTensors)
    return length(get_active_tensors(problem.static, problem.doms))
end

struct NumHardTensors <: AbstractMeasure end
function OptimalBranchingCore.measure(problem::TNProblem, ::NumHardTensors)
    active_tensors = get_active_tensors(problem.static, problem.doms)
    total_excess = 0
    for tensor_id in active_tensors
        vars = problem.static.tensors[tensor_id].var_axes
        degree = 0
        @inbounds for var in vars
            !is_fixed(problem.doms[var]) && (degree += 1)
        end
        degree > 2 && (total_excess += (degree - 2))
    end
    return total_excess
end

struct HardSetSize <: AbstractMeasure end
function OptimalBranchingCore.measure(problem::TNProblem, ::HardSetSize)
    hard_tensor_ids = Int[]
    
    # Find all hard tensors (degree > 2)
    @inbounds for tensor_id in 1:length(problem.static.tensors)
        vars = problem.static.tensors[tensor_id].var_axes
        degree = 0
        @inbounds for var_id in vars
            !is_fixed(problem.doms[var_id]) && (degree += 1)
        end
        degree > 2 && push!(hard_tensor_ids, tensor_id)
    end
    
    # If no hard tensors, return 0
    isempty(hard_tensor_ids) && return 0
    
    # Build mapping: hard_tensor_id -> index in the cover problem
    hard_tensor_index = Dict{Int, Int}()
    for (idx, tid) in enumerate(hard_tensor_ids)
        hard_tensor_index[tid] = idx
    end
    num_hard_tensors = length(hard_tensor_ids)
    
    # Build variable -> hard tensors mapping
    # var_covers[var_id] = list of hard tensor indices that contain this variable
    var_covers = [Vector{Int}() for _ in 1:length(problem.doms)]
    @inbounds for (idx, tensor_id) in enumerate(hard_tensor_ids)
        vars = problem.static.tensors[tensor_id].var_axes
        @inbounds for var_id in vars
            !is_fixed(problem.doms[var_id]) && push!(var_covers[var_id], idx)
        end
    end
    
    # Filter out variables that don't cover any hard tensor
    subsets = Vector{Vector{Int}}()
    for var_id in 1:length(var_covers)
        !isempty(var_covers[var_id]) && push!(subsets, var_covers[var_id])
    end
    
    # All variables have equal weight
    weights = ones(Int, length(subsets))
    
    # Solve weighted minimum set cover: select minimum variables to cover all hard tensors
    solver = OptimalBranchingCore.LPSolver(verbose=false, optimizer=Gurobi.Optimizer(GRB_ENV[]))
    selected = OptimalBranchingCore.weighted_minimum_set_cover(solver, weights, subsets, num_hard_tensors)
    return length(selected)
end

