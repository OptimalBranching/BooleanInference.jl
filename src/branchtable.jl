struct TNContractionSolver <: AbstractTableSolver 
    k::Int  # number of hops
    max_tensors::Int
end
TNContractionSolver() = TNContractionSolver(1, 2)

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

function handle_no_boundary_case_unfixed(
    region::Region,
    contracted::AbstractArray{Tropical{Float64}},
    inner_output_vars::Vector{Int},
)
    n_inner = length(region.inner_vars)
    free_inner_configs = extract_inner_configs(contracted, length(inner_output_vars))
    
    if !isempty(free_inner_configs)
        # All variables are unfixed, directly convert configs
        return BranchingTable(n_inner, [free_inner_configs])
    else
        return BranchingTable(0, [Int[]])
    end
end

function create_region(problem::TNProblem, variable::Int, solver::TNContractionSolver)
    # Compute k-neighboring region using all-unfixed domains
    # This ensures the region is consistent across different branches
    all_unfixed_doms = fill(DM_BOTH, length(problem.doms))
    k_neighboring(problem.static, all_unfixed_doms, variable; max_tensors = solver.max_tensors, k = solver.k)
end

# Filter cached BranchingTable: filter rows by fixed values, extract columns for unfixed vars
function filter_branching_table(region::Region, table::BranchingTable, problem::TNProblem)
    # Get all variable IDs in order: boundary_vars + inner_vars
    var_ids = vcat(region.boundary_vars, region.inner_vars)
    n_vars = length(var_ids)

    # Separate fixed and unfixed positions
    fixed_positions = Tuple{Int, Bool}[]  # (position, required_value)
    unfixed_positions = Int[]             # positions to extract

    @inbounds for (i, var_id) in enumerate(var_ids)
        if is_fixed(problem.doms[var_id])
            required_value = has1(problem.doms[var_id])
            push!(fixed_positions, (i, required_value))
        else
            push!(unfixed_positions, i)
        end
    end

    # If no variables are fixed, return the original table with all vars
    if isempty(fixed_positions)
        return table, var_ids
    end

    n_unfixed = length(unfixed_positions)

    # Filter and extract configs
    filtered_table = similar(table.table, 0)
    sizehint!(filtered_table, length(table.table))

    @inbounds for config_group in table.table
        filtered_group = similar(config_group, 0)
        sizehint!(filtered_group, length(config_group))

        for config_bits in config_group
            # Check if this config matches all fixed variable values
            matches = true
            for (pos, required_val) in fixed_positions
                bit_val = OptimalBranchingCore.readbit(config_bits, pos)
                if (bit_val == 1) != required_val
                    matches = false
                    break
                end
            end

            if matches
                # Extract bits for unfixed variables into a new config
                new_config_int = 0
                for (new_pos, old_pos) in enumerate(unfixed_positions)
                    bit_val = OptimalBranchingCore.readbit(config_bits, old_pos)
                    if bit_val == 1
                        new_config_int |= (1 << (new_pos - 1))
                    end
                end
                # Convert to same type as original config
                new_config = typeof(config_bits)(new_config_int)
                push!(filtered_group, new_config)
            end
        end

        # Only add groups that have at least one matching config
        if !isempty(filtered_group)
            push!(filtered_table, filtered_group)
        end
    end

    # Return empty table if no configs match
    if isempty(filtered_table)
        return BranchingTable(0, eltype(table.table)[]), Int[]
    end

    # Return filtered table with new bit_length for unfixed vars only
    unfixed_var_ids = [var_ids[i] for i in unfixed_positions]
    return BranchingTable(n_unfixed, filtered_table), unfixed_var_ids
end

function OptimalBranchingCore.branching_table(problem::TNProblem, solver::TNContractionSolver, variable::Int)
    cached_region, cached_table = get_cached_region(variable)
    if !isnothing(cached_region) && !isnothing(cached_table)
        filtered_table, unfixed_vars = filter_branching_table(cached_region, cached_table, problem)
        return filtered_table, unfixed_vars
    end

    # Cache miss - recompute
    region = create_region(problem, variable, solver)
    n_boundary = length(region.boundary_vars)
    n_inner = length(region.inner_vars)
    n_total = n_boundary + n_inner
    
    # Contract with all-unfixed doms for consistent caching
    all_unfixed_doms = fill(DM_BOTH, length(problem.doms))
    contracted_tensor, output_vars = contract_region(problem.static, region, all_unfixed_doms)
    axismap = _build_axismap(output_vars)

    inner_output_vars = Int[]
    @inbounds for var_id in output_vars
        if var_id in region.inner_vars
            push!(inner_output_vars, var_id)
        end
    end

    if n_boundary == 0
        table = handle_no_boundary_case_unfixed(region, contracted_tensor, inner_output_vars)
        variables = vcat(region.boundary_vars, region.inner_vars)
        cache_region_table!(region, table)
        # Filter based on current doms before returning
        filtered_table, unfixed_vars = filter_branching_table(region, table, problem)
        return filtered_table, unfixed_vars
    end
    
    # All vars are unfixed in cached version, so all boundary vars are free
    free_boundary_vars = region.boundary_vars
    free_boundary_indices = collect(1:n_boundary)
    
    n_free_boundary = length(free_boundary_vars)
    
    inner_posmap = _build_axismap(inner_output_vars)
    
    valid_config_groups = Vector{Vector{Vector{Bool}}}()
    assignments = Tuple{Int,Bool}[]
    resize!(assignments, n_free_boundary)
    
    for free_config in 0:(2^n_free_boundary - 1)
        for (j, var_id) in enumerate(free_boundary_vars)
            bit = (free_config >> (j-1)) & 0x1
            assignments[j] = (var_id, bit == 1)
        end
        
        contracted_slice = slice_region_contraction(contracted_tensor, assignments, axismap)
        
        free_inner_configs = extract_inner_configs(contracted_slice, length(inner_output_vars))
        
        isempty(free_inner_configs) && continue
        
        # Construct configs: all vars are unfixed, so directly use bit values
        boundary_config = Vector{Bool}(undef, n_boundary)
        @inbounds for i in 1:n_boundary
            bit = (free_config >> (i-1)) & 0x1
            boundary_config[i] = (bit == 1)
        end
         
        full_configs = combine_configs(boundary_config, free_inner_configs)
        
        push!(valid_config_groups, full_configs)
    end
    
    if isempty(valid_config_groups)
        table = BranchingTable(0, [Int[]])
        cache_region_table!(region, table)
        return table, Int[]
    end
    
    table = BranchingTable(n_total, valid_config_groups)
    cache_region_table!(region, table)
    
    # Filter based on current doms before returning
    filtered_table, unfixed_vars = filter_branching_table(region, table, problem)
    return filtered_table, unfixed_vars
end
