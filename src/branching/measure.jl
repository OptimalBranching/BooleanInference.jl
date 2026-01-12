# ============================================================================
# Problem Measures
#
# Measures quantify problem size/difficulty and guide branching decisions.
# The branching algorithm aims to minimize the measure as quickly as possible.
# ============================================================================

"""
    NumUnfixedVars <: AbstractMeasure

Measure the problem size by counting unfixed variables.

This is the simplest measure and works well for problems where
all constraints have similar difficulty.
"""
struct NumUnfixedVars <: AbstractMeasure end

function measure_core(::ConstraintNetwork, doms::Vector{DomainMask}, ::NumUnfixedVars)
    return count_unfixed(doms)
end

function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedVars)
    return count_unfixed(problem)
end

"""
    NumUnfixedTensors <: AbstractMeasure

Measure the problem size by counting active (unfixed) tensors.

A tensor is active if it has at least one unfixed variable.
This measure prioritizes eliminating constraints over variables.
"""
struct NumUnfixedTensors <: AbstractMeasure end

function measure_core(cn::ConstraintNetwork, doms::Vector{DomainMask}, ::NumUnfixedTensors)
    return count_active_tensors(cn, doms)
end

function OptimalBranchingCore.measure(problem::TNProblem, ::NumUnfixedTensors)
    return measure_core(problem.static, problem.doms, NumUnfixedTensors())
end
