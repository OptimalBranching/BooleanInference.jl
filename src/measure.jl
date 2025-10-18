struct NumUnfixedVars <: AbstractMeasure end
function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedVars)
    # problem.n_unfixed == 0 && println("n_unfixed is 0")
    return Int(problem.n_unfixed)
end

# struct NumUnfixedTensors <: AbstractMeasure end
# function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedTensors)
#     problem.doms
# end

# struct NumUnfixedTensors <: AbstractMeasure end
# function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedTensors)
#     length(problem.ws.active_tensors)
# end

