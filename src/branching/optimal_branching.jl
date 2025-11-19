# Optimal branching rule selection for different solver types

# Calculate size reduction after applying a clause to the problem
# Uses evaluate_branch for trial evaluation and caching
function OptimalBranchingCore.size_reduction(p::TNProblem, m::OptimalBranchingCore.AbstractMeasure, cl::OptimalBranchingCore.Clause{INT}, variables::Vector{Int}) where {INT<:Integer}
    subproblem = evaluate_branch!(p, cl, variables, p.ws.temp_doms)
    reduction = OptimalBranchingCore.measure(p, m) - OptimalBranchingCore.measure(subproblem, m)
    return reduction
end

# GreedyMerge solver: use greedy merge algorithm
function OptimalBranchingCore.optimal_branching_rule(tbl::OptimalBranchingCore.BranchingTable, variables::Vector{T}, problem::TNProblem, measure::OptimalBranchingCore.AbstractMeasure, solver::OptimalBranchingCore.GreedyMerge) where T
    candidates = OptimalBranchingCore.bit_clauses(tbl)
    return OptimalBranchingCore.greedymerge(candidates, problem, variables, measure)
end

# Set cover solver: filter candidates and minimize γ
function OptimalBranchingCore.optimal_branching_rule(tbl::OptimalBranchingCore.BranchingTable{INT}, variables::Vector{T}, problem::TNProblem, measure::OptimalBranchingCore.AbstractMeasure, solver::OptimalBranchingCore.AbstractSetCoverSolver) where {INT<:Integer, T}
    candidates = OptimalBranchingCore.candidate_clauses(tbl)
    valid_clauses = Vector{OptimalBranchingCore.Clause{INT}}()
    reductions = Float64[]

    for clause in candidates
        reduction = Float64(OptimalBranchingCore.size_reduction(problem, measure, clause, variables))
        # Allow reduction >= 0 to ensure at least some progress is made
        # Even if reduction = 0, we still fix variables which may enable future progress
        if isfinite(reduction) && reduction >= 0
            push!(valid_clauses, clause)
            push!(reductions, reduction)
        end
    end

    if isempty(valid_clauses)
        empty_clauses = Vector{OptimalBranchingCore.Clause{INT}}()
        return OptimalBranchingCore.OptimalBranchingResult(OptimalBranchingCore.DNF(empty_clauses), Float64[], Inf)
    end

    covered_mask = BitVector(undef, length(tbl.table))
    @inbounds for (idx, group) in pairs(tbl.table)
        covered_mask[idx] = any(valid_clauses) do clause
            any(config -> OptimalBranchingCore.covered_by(config, clause), group)
        end
    end

    if !all(covered_mask)
        if !any(covered_mask)
            empty_clauses = Vector{OptimalBranchingCore.Clause{INT}}()
            return OptimalBranchingCore.OptimalBranchingResult(OptimalBranchingCore.DNF(empty_clauses), Float64[], Inf)
        end
        filtered_groups = tbl.table[findall(covered_mask)]
        tbl = OptimalBranchingCore.BranchingTable{INT}(tbl.bit_length, filtered_groups)
    end

    return OptimalBranchingCore.minimize_γ(tbl, valid_clauses, reductions, solver)
end

# NaiveBranch solver: filter infeasible branches then use naive branching
function OptimalBranchingCore.optimal_branching_rule(tbl::OptimalBranchingCore.BranchingTable{INT}, variables::Vector{T}, problem::TNProblem, measure::OptimalBranchingCore.AbstractMeasure, solver::OptimalBranchingCore.NaiveBranch) where {INT<:Integer, T}
    candidates = OptimalBranchingCore.bit_clauses(tbl)
	size_reductions = [OptimalBranchingCore.size_reduction(problem, measure, candidate[1], variables) for candidate in candidates]
    # filter the size_reductions that is not -Inf
    valid_idx = findall(size_reductions .!= -Inf)
    size_reductions = size_reductions[valid_idx]
    valid_clauses = [candidate[1] for candidate in candidates[valid_idx]]

    if isempty(valid_clauses)
        empty_clauses = Vector{OptimalBranchingCore.Clause{INT}}()
        return OptimalBranchingCore.OptimalBranchingResult(OptimalBranchingCore.DNF(empty_clauses), Float64[], Inf)
    end

	γ = OptimalBranchingCore.complexity_bv(size_reductions)
    return OptimalBranchingResult(DNF(valid_clauses), size_reductions, γ)
end

# No-op reducer (used when no reduction is applied)
function OptimalBranchingCore.reduce_problem(::Type{T}, problem::TNProblem, ::OptimalBranchingCore.NoReducer) where T
    return (problem, one(T))
end
