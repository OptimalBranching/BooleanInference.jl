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