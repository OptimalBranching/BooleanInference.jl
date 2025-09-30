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

"""
	deduction_reduce(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, reducing_queue::Vector{Int})

Deduction reduce the problem by using the deduction rule.
"""
function deduction_reduce(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, reducing_queue::Vector{Int})
	while !isempty(reducing_queue)
		isempty(reducing_queue) && break
		# take the first edge from the reducing_queue
		edge_idx = popfirst!(reducing_queue)
		# if the edge is already decided, skip
		(bs.undecided_literals[edge_idx] <= 0) && continue
		# check if the edge can be reduced
		zerocount, sumpos = check_reduce(p.he2v[edge_idx], bs.decided_mask, bs.config, p.tensors[edge_idx])
		# only have one way to make the edge satisfiable
		(zerocount == 1) || continue
		# using this unique way to make the edge satisfiable
		bs, aedges = decide_literal(bs, p, p.he2v[edge_idx], Clause(2^length(p.he2v[edge_idx]) - 1, sumpos - 1))
		# add the edges that have been changed to the reducing_queue again
		reducing_queue = append!(reducing_queue, aedges)
	end
	return bs
end

function check_reduce(he2vi, mask, config, tensor)
	# This function checks how many ways can make the edge satisfiable by assigning values to the undecided literals
	count = 0
	sum = 0
	decided_literal_num = 0
	for j in 1:length(he2vi)
		if readbit(mask, he2vi[j]) == 1  # if the literal is decided
			sum += Int(readbit(config, he2vi[j])) * (1 << (j - 1))
			decided_literal_num += 1
		end
	end
	# enumerate all possible values of the undecided literals
	# If there is no undecided literal, the floop will be run once.
	sumpos = 0
	for i in 0:2^(length(he2vi)-decided_literal_num)-1
		sum1 = sum
		counti = 0
		for j in 1:length(he2vi)
			if !(readbit(mask, he2vi[j]) == 1)  # if the literal is not decided
				counti += 1
				sum1 += Int(readbit(i, counti)) * (1 << (j - 1))
			end
		end
		if tensor[sum1+1] == Tropical(0.0) # if the configuration is feasible
			count += 1  # count the number of feasible configurations
			sumpos = sum1 + 1  # the flattened index of the feasible configuration
		end
	end
	return count, sumpos
end

function decide_literal(bs::AbstractBranchingStatus{C}, p::BooleanInferenceProblem, vertices::Vector{Int}, clause::Clause{N}) where {N,C}
	config = copy(bs.config)  # The value of variables 

	dls = Int[]
	for (k, v) in enumerate(vertices)  # enumerate the vertices in the clause
		if readbit(clause.mask, k) == 1 && (readbit(bs.decided_mask, v) == 0)
			push!(dls, v)  # the undecided literals in the clause
			if readbit(clause.val, k) == 1
				# Set the v-th bit of config to 1
				config = config | LongLongUInt{C}(1) << (v - 1)
			end
		end
	end
	mask = bs.decided_mask | indices_to_mask(dls, typeof(config))
	undecided_literals = copy(bs.undecided_literals)
	aedges = Int[]  # edges that have been changed
	# get the union of edges that contain the undecided literals
	for edge_num in mapreduce(v -> p.v2he[v], ∪, dls)
		# if the edge is not fully decided
		if bs.undecided_literals[edge_num] > 0
			# In each edge, how many variables are newly decided
			decided_num = count(x -> x in dls, p.he2v[edge_num])
			# how many ways can make the edge satisfiable under the current configuration
			zerocount, _ = check_reduce(p.he2v[edge_num], mask, config, p.tensors[edge_num])

			if (zerocount == 2^(undecided_literals[edge_num] - decided_num))
				# after the vertices in url are decided, the edge is always satisfiable
				undecided_literals[edge_num] = -1  
			else
				undecided_literals[edge_num] -= decided_num
				push!(aedges, edge_num)
			end
		end
	end
	return BranchingStatus(config, mask, undecided_literals), aedges
end