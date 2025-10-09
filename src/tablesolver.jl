"""
    TNContractionSolver <: AbstractTableSolver

A table solver that uses tensor network contraction to compute branching tables.
This solver enumerates all possible configurations of boundary variables and uses
tensor network contraction to determine feasible internal variable assignments.
"""
struct TNContractionSolver <: AbstractTableSolver end

"""
    branching_table(bip::BooleanInferenceProblem, bs::AbstractBranchingStatus, solver::TNContractionSolver, subbip::SubBIP)

Compute a branching table for the given subproblem using tensor network contraction.

# Arguments
- `bip`: The boolean inference problem
- `bs`: Current branching status
- `solver`: The TNContractionSolver instance
- `subbip`: Subproblem containing selected variables and their associated tensor data

# Returns
- `BranchingTable`: Contains all possible branching configurations for the subproblem

# Algorithm
1. Enumerate all possible configurations of boundary variables (variables connected to external clauses)
2. For each boundary configuration, use tensor network contraction to find feasible internal variable assignments
3. Group configurations by boundary variable assignments
4. Return a branching table containing all valid branching decisions

The function uses the following key concepts:
- **Boundary variables**: Variables that appear in clauses outside the current subproblem
- **Internal variables**: Variables that only appear in clauses within the current subproblem  
- **Tensor contraction**: Efficiently computes the feasibility of variable assignments using tropical arithmetic
"""
function branching_table(bip::BooleanInferenceProblem, bs::AbstractBranchingStatus, solver::TNContractionSolver, subbip::SubBIP)
	out_vs_num = length(subbip.outside_vs_ind)
	vs_num = length(subbip.vs)
	
	# Create index mapping: for each variable, find its position in either boundary or internal variable lists
	ind_pos = [i ∈ subbip.outside_vs_ind ? findfirst(==(i), subbip.outside_vs_ind) : findfirst(==(i), setdiff(1:vs_num, subbip.outside_vs_ind)) for i in 1:vs_num]
	
	# Store all possible branching configurations
	possible_configurations = Vector{Vector{Bool}}[]
	
	# Enumerate all possible configurations of boundary variables (2^out_vs_num possibilities)
	for config_idx in 0:(2^out_vs_num-1)
		# Convert integer config_idx to binary representation for boundary variables
		answer = [config_idx & (1 << j) != 0 for j in 0:out_vs_num-1]
		# Convert boolean values to tensor indices (true -> 2, false -> 1)
		out_index = [bit ? 2 : 1 for bit in answer]
		
		# Create tensor access vector: boundary variables get specific indices, internal variables get (:)
		vec = [var_idx ∈ subbip.outside_vs_ind ? out_index[ind_pos[var_idx]] : (:) for var_idx in 1:vs_num]
		
		# Slice by the fixed boundary 
		# Find all positions where the contracted tensor equals Tropical(0.0) (feasible)
		sub_tensors = @view subbip.sub_tensors[vec...]
		in_indies = findall(==(Tropical(0.0)), sub_tensors)
		
		# Skip this boundary configuration if no feasible internal assignments exist
		if length(in_indies) == 0
			continue
		end
		
		# Generate all possible configurations for this boundary assignment
		# Each configuration specifies assignments for both boundary and internal variables
		# pcs = [[var_idx ∈ subbip.outside_vs_ind ? out_index[ind_pos[var_idx]] : in_index[ind_pos[var_idx]] for var_idx in 1:vs_num] .== fill(2, vs_num) for in_index in in_indies]
		pcs = Vector{Vector{Bool}}(undef, length(in_indies))
		for (k, in_index) in pairs(in_indies)
			assignment = Vector{Bool}(undef, vs_num)
			@inbounds for var_idx in 1:vs_num
				val = var_idx ∈ subbip.outside_vs_ind ? 
					out_index[ind_pos[var_idx]] : 
					in_index[ind_pos[var_idx]]
				assignment[var_idx] = (val == 2)
			end
			pcs[k] = assignment
		end
		push!(possible_configurations, pcs)
	end
	
	# Return empty branching table if no feasible configurations found, otherwise return the computed table
	isempty(possible_configurations) ? (return BranchingTable(0,[Int[]])) : (return BranchingTable(vs_num, possible_configurations))
end
