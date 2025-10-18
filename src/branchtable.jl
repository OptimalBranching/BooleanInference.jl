using OptimalBranchingCore: BranchingTable

struct TNContractionSolver <: AbstractTableSolver end

function _build_axismap(output_vars::Vector{Int})
    isempty(output_vars) && return Int[]
    max_var = maximum(output_vars)
    axismap = zeros(Int, max_var)
    @inbounds for (idx, var_id) in enumerate(output_vars)
        axismap[var_id] = idx
    end
    return axismap
end

function separate_fixed_free_boundary(region::Region, doms::Vector{DomainMask})
    fixed_vars = Int[]; fixed_vals = Int[]; free_vars = Int[]; free_indices = Int[]
    
    for (i, var_id) in enumerate(region.boundary_vars)
        if is_fixed(doms[var_id])
            push!(fixed_vars, var_id)
            push!(fixed_vals, has1(doms[var_id]) ? 1 : 0)
        else
            push!(free_vars, var_id)
            push!(free_indices, i)
        end
    end
    
    return fixed_vars, fixed_vals, free_vars, free_indices
end

function construct_boundary_config(region::Region, doms::Vector{DomainMask}, free_pos_of_boundary::Vector{Int}, free_config::Int)
    n_boundary = length(region.boundary_vars)
    boundary_config = Vector{Bool}(undef, n_boundary)
    
    @inbounds for i in 1:n_boundary
        var_id = region.boundary_vars[i]
        if is_fixed(doms[var_id])
            boundary_config[i] = has1(doms[var_id])
        else
            j = free_pos_of_boundary[i]
            bit = (free_config >> (j-1)) & 0x1
            boundary_config[i] = (bit == 1)
        end
    end
    
    return boundary_config
end

function construct_inner_config(region::Region, doms::Vector{DomainMask}, inner_posmap::Vector{Int}, free_inner_configs::Vector{Vector{Bool}})
    n_inner = length(region.inner_vars)
    n_config = length(free_inner_configs)
    inner_configs = Vector{Vector{Bool}}(undef, n_config)

    @inbounds for config_idx in 1:n_config
        inner_config = Vector{Bool}(undef, n_inner)
        for i in 1:n_inner
            var_id = region.inner_vars[i]
            if is_fixed(doms[var_id])
                inner_config[i] = has1(doms[var_id])
            else
                j = inner_posmap[var_id]
                inner_config[i] = free_inner_configs[config_idx][j]
            end
        end
        inner_configs[config_idx] = inner_config
    end
    
    return inner_configs
end

function extract_inner_configs(contracted::AbstractArray{T, N}, n_inner::Int) where {T, N}
    @assert n_inner == N
    configs = Vector{Vector{Bool}}()
    one_tropical = one(Tropical{Float64})
    
    @inbounds for lin in eachindex(contracted)
        if contracted[lin] == one_tropical
            config = Vector{Bool}(undef, n_inner)
            linear_idx = LinearIndices(contracted)[lin] - 1
            for i in 1:n_inner
                config[i] = ((linear_idx >> (i-1)) & 0x1) == 1
            end
            push!(configs, config)
        end
    end
    return configs
end

function combine_configs(boundary_config::Vector{Bool}, inner_configs::Vector{Vector{Bool}})
    n_configs = length(inner_configs)
    n_boundary = length(boundary_config)
    n_inner = isempty(inner_configs) ? 0 : length(inner_configs[1])
    n_total = n_boundary + n_inner
    
    full_configs = Vector{Vector{Bool}}(undef, n_configs)
    
    @inbounds for i in 1:n_configs
        full_config = Vector{Bool}(undef, n_total)
        copyto!(full_config, 1, boundary_config, 1, n_boundary)
        copyto!(full_config, n_boundary + 1, inner_configs[i], 1, n_inner)
        full_configs[i] = full_config
    end
    
    return full_configs
end

function get_region_contraction(problem::TNProblem, region::Region)
    cached = get_cached_region_contraction(problem; region_id=region.id)
    if isnothing(cached)
        @debug "contract_region_cache_miss" focus=region.id
        contracted, output_vars = contract_region(problem.static, region, problem.doms)
        cache_region_contraction!(problem, contracted, output_vars; region_id=region.id)
        return contracted, output_vars
    else
        @debug "contract_region_cache_hit" focus=region.id
        return cached
    end
end

function slice_region_contraction(
    tensor::AbstractArray{Tropical{Float64}},
    assignments::Vector{Tuple{Int,Bool}},
    axismap::Vector{Int},
)
    isempty(assignments) && return tensor
    nd = ndims(tensor)
    nd == 0 && return tensor

    indices = Any[Colon() for _ in 1:nd]
    
    @inbounds for (var_id, value) in assignments
        axis = axismap[var_id]
        @assert axis > 0 "Boundary variable $var_id not found in contraction axes"
        indices[axis] = value ? 2 : 1
    end

    return @view tensor[indices...]
end

function handle_no_boundary_case(
    problem::TNProblem,
    region::Region,
    contracted::AbstractArray{Tropical{Float64}},
    inner_output_vars::Vector{Int},
)
    n_inner = length(region.inner_vars)
    
    free_inner_configs = extract_inner_configs(contracted, length(inner_output_vars))
    
    if !isempty(free_inner_configs)
        inner_posmap = _build_axismap(inner_output_vars)
        inner_configs = construct_inner_config(
            region, problem.doms, inner_posmap, free_inner_configs
        )
        return BranchingTable(n_inner, [inner_configs])
    else
        return BranchingTable(0, [Int[]])
    end
end

function OptimalBranchingCore.branching_table(
    problem::TNProblem, 
    solver::TNContractionSolver, 
    variables::Vector{T}
) where T
    region = get_cached_region(problem)
    isnothing(region) && error("No cached region found. Make sure `select_variables` is called first.")
    
    n_boundary = length(region.boundary_vars)
    n_inner = length(region.inner_vars)
    n_total = n_boundary + n_inner
    @assert n_total == length(variables)
    
    contracted_tensor, output_vars = get_region_contraction(problem, region)
    axismap = _build_axismap(output_vars)

    inner_output_vars = Int[]
    @inbounds for var_id in output_vars
        if var_id in region.inner_vars
            push!(inner_output_vars, var_id)
        end
    end

    if n_boundary == 0
        return handle_no_boundary_case(problem, region, contracted_tensor, inner_output_vars)
    end
    
    _, _, free_boundary_vars, free_boundary_indices = 
        separate_fixed_free_boundary(region, problem.doms)
    
    n_free_boundary = length(free_boundary_vars)
    
    free_pos_of_boundary = zeros(Int, n_boundary)
    @inbounds for (j, boundary_idx) in enumerate(free_boundary_indices)
        free_pos_of_boundary[boundary_idx] = j
    end
    
    inner_posmap = _build_axismap(inner_output_vars)
    
    valid_config_groups = Vector{Vector{Vector{Bool}}}()
    
    assignments = Tuple{Int,Bool}[]
    resize!(assignments, n_free_boundary)
    
    for free_config in 0:(2^n_free_boundary - 1)
        for (j, var_id) in enumerate(free_boundary_vars)
            bit = (free_config >> (j-1)) & 0x1
            assignments[j] = (var_id, bit == 1)
        end
        
        contracted_slice = slice_region_contraction(
            contracted_tensor,
            assignments,
            axismap,
        )
        
        free_inner_configs = extract_inner_configs(contracted_slice, length(inner_output_vars))
        
        isempty(free_inner_configs) && continue
        
        boundary_config = construct_boundary_config(region, problem.doms, free_pos_of_boundary, free_config)

        inner_configs = construct_inner_config(region, problem.doms, inner_posmap, free_inner_configs)
         
        full_configs = combine_configs(boundary_config, inner_configs)
        
        push!(valid_config_groups, full_configs)
    end
    
    if isempty(valid_config_groups)
        return BranchingTable(0, [Int[]])
    end
    
    return BranchingTable(n_total, valid_config_groups)
end
