struct NoReducer <: AbstractReducer end
struct RuleReducer <: AbstractReducer # Rules from paper "Fast Exact Algorithms for the SAT Problem with Bounded Occurrences of Variables"
	rules::Vector{Int}
end
function OptimalBranchingCore.reduce_problem(p::BooleanInferenceProblem, bs::AbstractBranchingStatus,reducer::NoReducer)
	return bs
end
function OptimalBranchingCore.reduce_problem(p::BooleanInferenceProblem, bs::AbstractBranchingStatus,reducer::RuleReducer)
	if 4 ∈ reducer.rules
		bs = reduction_4(p, bs)
	end
	return bs
end
function reduction_4(p::BooleanInferenceProblem, bs::AbstractBranchingStatus)
	# Rule 4: If x is true in all clauses, set x to true.
	for (i, undecided_literal_num) in enumerate(bs.undecided_literals)
		if undecided_literal_num == 1
			edge = p.he2v[i]
			undecided_literal = findfirst(x -> readbit(bs.decided_mask, x) == 0, edge)
			bs.decided_mask = bs.decided_mask | LongLongUInt(1) << (undecided_literal - 1)
			bs.config = bs.config & (~(LongLongUInt(1) << (undecided_literal - 1)))
			bs.undecided_literals[i] = -1
		end
	end
	return bs
end

function deduction_reduce(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, reducing_queue::Vector{Int})
	while !isempty(reducing_queue)
		isempty(reducing_queue) && break
		edge_num = popfirst!(reducing_queue)
		(bs.undecided_literals[edge_num] <= 0) && continue

		zerocount, sumpos = check_reduce(p.he2v[edge_num], bs.decided_mask,bs.config, p.tensors[edge_num])
		(zerocount == 1) || continue

		bs, aedges = decide_literal(bs, p, p.he2v[edge_num], Clause(2^length(p.he2v[edge_num]) - 1, sumpos - 1))

		reducing_queue = reducing_queue ∪ aedges
	end
	return bs
end

function check_reduce(he2vi, mask, config, tensor)
	count = 0
	sum = 0
	decided_literal_num = 0
	for j in 1:length(he2vi)
		if readbit(mask, he2vi[j]) == 1
			sum += Int(readbit(config, he2vi[j])) * (1 << (j - 1))
			decided_literal_num += 1
		end
	end
	sumpos = 0
	for i in 0:2^(length(he2vi)-decided_literal_num)-1
		sum1 = sum
		counti = 0
		for j in 1:length(he2vi)
			if !(readbit(mask, he2vi[j]) == 1)
				counti += 1
				sum1 += (1 << (j - 1)) * readbit(i, counti)
			end
		end
		if tensor[sum1+1] == Tropical(0.0)
			count += 1
			sumpos = sum1 + 1
		end
	end
	return count, sumpos
end

function decide_literal(bs::AbstractBranchingStatus{C}, p::BooleanInferenceProblem, vertices::Vector{Int}, clause::Clause{N}) where {N,C}
	config = copy(bs.config)
	# mask = copy(bs.decided_mask)
	dls = Int[]
	for (k, v) in enumerate(vertices)
		if readbit(clause.mask, k) == 1 && (readbit(bs.decided_mask, v) == 0)
			push!(dls, v)
			# mask = mask | LongLongUInt{C}(1) << (v - 1)
			if readbit(clause.val, k) == 1
				config = config | LongLongUInt{C}(1) << (v - 1)
			end
		end
	end
	mask = bs.decided_mask | vec2lluint(dls, typeof(config))
	undecided_literals = copy(bs.undecided_literals)
	aedges = Int[] # Edges that have been changed
	for edge_num in mapreduce(v -> p.v2he[v], ∪, dls)
		if bs.undecided_literals[edge_num] > 0
			zerocount, _ = check_reduce(p.he2v[edge_num], mask, config, p.tensors[edge_num])

			decided_num = count(x -> x in dls, p.he2v[edge_num])
			# edge_mask = vec2lluint(p.he2v[edge_num], typeof(config))
			# decided_num = count_ones(edge_mask & mask) - count_ones(edge_mask & bs.decided_mask)

			if (zerocount == 2^(undecided_literals[edge_num] - decided_num))
				undecided_literals[edge_num] = -1
			else
				undecided_literals[edge_num] -= decided_num
				push!(aedges, edge_num)
			end
		end
	end
	return BranchingStatus(config, mask, undecided_literals), aedges
end