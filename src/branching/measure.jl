struct NumUnfixedVars <: AbstractMeasure end
function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedVars)
    return Int(problem.n_unfixed)
end

struct NumUnfixedTensors <: AbstractMeasure end
function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedTensors)
    return length(get_active_tensors(problem.static, problem.doms))
end

struct NumHardTensors <: AbstractMeasure end
function OptimalBranchingCore.measure(problem::TNProblem, ::NumHardTensors)
    active_tensors = get_active_tensors(problem.static, problem.doms)
    hard_tensor_num = 0
    for tensor_id in active_tensors
        vars = problem.static.tensors[tensor_id].var_axes
        degree = 0
        for var in vars
            if !is_fixed(problem.doms[var])
                degree += 1
            end
        end
        if degree > 2
            hard_tensor_num += 1
        end
    end
    return hard_tensor_num
end