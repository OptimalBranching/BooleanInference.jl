struct NumUnfixedVars <: AbstractMeasure end

function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedVars)
    # problem.n_unfixed == 0 && println("n_unfixed is 0")
    return Int(problem.n_unfixed)
end
