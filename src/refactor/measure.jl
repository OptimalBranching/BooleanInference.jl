# Measure implementations for TNProblem

"""
    NumUnfixedVars <: AbstractMeasure

Counts the number of unfixed variables in the problem.
"""
struct NumUnfixedVars <: AbstractMeasure end

function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedVars)
    return Int(problem.n_unfixed)
end

