struct TNContractionSolver <: AbstractTableSolver end

function OptimalBranchingCore.branching_table(bip::BooleanInferenceProblem, bs::AbstractBranchingStatus,solver::TNContractionSolver, subbip::SubBIP)

	out_vs_num = length(subbip.outside_vs_ind)
	vs_num = length(subbip.vs)
	ind_pos = [i ∈ subbip.outside_vs_ind ? findfirst(==(i), subbip.outside_vs_ind) : findfirst(==(i), setdiff(1:vs_num, subbip.outside_vs_ind)) for i in 1:vs_num]
	possible_configurations = Vector{Vector{Bool}}[]
	for i in 0:(2^out_vs_num-1)
		answer = [i & (1 << j) != 0 for j in 0:out_vs_num-1]
		out_index = [i ? 2 : 1 for i in answer]
		vec = [i ∈ subbip.outside_vs_ind ? out_index[ind_pos[i]] : (:) for i in 1:vs_num]
		in_indies = findall(==(Tropical(0.0)), subbip.sub_tensors[vec...])
		if length(in_indies) == 0
			continue
		end
		pcs = [[i ∈ subbip.outside_vs_ind ? out_index[ind_pos[i]] : in_index[ind_pos[i]] for i in 1:vs_num] .== fill(2, vs_num) for in_index in in_indies]
		push!(possible_configurations, pcs)
	end
	# @show possible_configurations
	isempty(possible_configurations) ? (return BranchingTable(0,[Int[]])) : (return BranchingTable(vs_num, possible_configurations))
end