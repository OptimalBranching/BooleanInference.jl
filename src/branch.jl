function OptimalBranchingCore.apply_branch(p::BooleanInferenceProblem, bs::AbstractBranchingStatus,clause::Clause{INT}, vertices::Vector{T}) where {INT<:Integer, T<:Integer}
    bs_new, aedges = decide_literal(bs,p, vertices, clause)
    return deduction_reduce(p, bs_new, aedges)
end

function OptimalBranchingCore.branch_and_reduce(problem::BooleanInferenceProblem, bs::AbstractBranchingStatus,config::BranchingStrategy, reducer::AbstractReducer)
    stopped, res,count_num = check_stopped(bs)
    stopped && return res, bs,count_num

    # branch the problem
    subbip = select_variables(problem, bs, config.measure, config.selector)  # select a subset of variables
    tbl = branching_table(problem,bs, config.table_solver, subbip)      # compute the BranchingTable
    iszero(tbl.bit_length) && return false,bs,1

    result = optimal_branching_rule(tbl, subbip.vs, bs,problem, config.measure, config.set_cover_solver)  # compute the optimal branching rule
    for branch in OptimalBranchingCore.get_clauses(result)
        res, bs_new ,count_num1= branch_and_reduce(problem, apply_branch(problem,bs, branch, subbip.vs), config, reducer)
        count_num += count_num1
        if res
            return res, bs_new,count_num
        end
    end
    return false, bs,count_num
end

function check_stopped(bs::AbstractBranchingStatus)
    # global BRANCHNUMBER
    # if there is no clause, then the problem is solved.
    if all(bs.undecided_literals .== -1)
        # BRANCHNUMBER += 1
        return true,true,1
    end
    if any(bs.undecided_literals .== 0)
        # BRANCHNUMBER += 1
        return true,false,1
    end
    return false,false,0
end

function OptimalBranchingCore.optimal_branching_rule(table::BranchingTable, variables::Vector, bs::AbstractBranchingStatus,p::BooleanInferenceProblem, m::AbstractMeasure, solver::AbstractSetCoverSolver)
    candidates = collect(candidate_clauses(table))
    size_reductions = [measure(bs, m) - measure((apply_branch(p,bs, candidate, variables)), m) for candidate in candidates]
    return minimize_γ(table, candidates, size_reductions, solver; γ0=2.0)
end

function mybranch_and_reduce(problem::BooleanInferenceProblem, bs::AbstractBranchingStatus,config::BranchingStrategy, reducer::AbstractReducer)
    stopped, res = check_stopped(bs)
    stopped && return res, bs

    v = findfirst(x -> readbit(bs.decided_mask,x) == 0, 1:problem.literal_num)

    res, bs_new = branch_and_reduce(problem, apply_branch(problem,bs, Clause(0b1, 0b1), [v]), config, reducer)
    if res
        return res, bs_new
    end

    res, bs_new = branch_and_reduce(problem, apply_branch(problem,bs, Clause(0b1, 0b0), [v]), config, reducer)
    if res
        return res, bs_new
    end

    return false, bs
end

function OptimalBranchingCore.optimal_branching_rule(table::BranchingTable, variables::Vector, bs::AbstractBranchingStatus,p::BooleanInferenceProblem, m::AbstractMeasure, solver::AbstractSetCoverSolver)
	candidates = OptimalBranchingCore.bit_clauses(table)
	return OptimalBranchingCore.greedymerge(candidates, p,bs, variables, m)
end

# TODO: NOT DRY!
function OptimalBranchingCore.greedymerge(cls::Vector{Vector{Clause{INT}}}, problem::AbstractProblem,bs::AbstractBranchingStatus, variables::Vector, m::AbstractMeasure) where {INT}
	active_cls = collect(1:length(cls))
	cls = copy(cls)
	merging_pairs = [(i, j) for i in active_cls, j in active_cls if i < j]
	n = length(variables)
	size_reductions = [OptimalBranchingCore.size_reduction(problem, m,bs, candidate[1], variables) for candidate in cls]
	γ = OptimalBranchingCore.complexity_bv(size_reductions)
	while !isempty(merging_pairs)
		i, j = popfirst!(merging_pairs)
		if i in active_cls && j in active_cls
			for ii in 1:length(cls[i]), jj in 1:length(cls[j])
				if OptimalBranchingCore.bdistance(cls[i][ii], cls[j][jj]) == 1
					cl12 = OptimalBranchingCore.gather2(n, cls[i][ii], cls[j][jj])
					if cl12.mask == 0
						continue
					end
					l12 = OptimalBranchingCore.size_reduction(problem, m,bs, cl12, variables)
					if γ^(-size_reductions[i]) + γ^(-size_reductions[j]) >= γ^(-l12) + 1e-8
						push!(cls, [cl12])
						k = length(cls)
						deleteat!(active_cls, findfirst(==(i), active_cls))
						deleteat!(active_cls, findfirst(==(j), active_cls))
						for ii in active_cls
							push!(merging_pairs, (ii, k))
						end
						push!(active_cls, k)
						push!(size_reductions, l12)
						γ = OptimalBranchingCore.complexity_bv(size_reductions[active_cls])
						break
					end
				end
			end
		end
	end
	return [cl[1] for cl in cls[active_cls]]
end

function OptimalBranchingCore.size_reduction(p::AbstractProblem, m::AbstractMeasure,bs::AbstractBranchingStatus, cl::Clause{INT}, variables::Vector) where {INT}
	return measure(bs, m) - measure(apply_branch(p,bs, cl, variables), m)
end
