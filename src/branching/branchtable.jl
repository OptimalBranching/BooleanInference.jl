struct TNContractionSolver <: AbstractTableSolver 
    k::Int
    max_tensors::Int
end
TNContractionSolver() = TNContractionSolver(1, 2)

@inline function bit_extract(config::UInt64, positions::Vector{Int})::UInt64
    out::UInt64 = 0
    @inbounds for (newpos, oldpos) in enumerate(positions)
        out |= ((config >> (oldpos-1)) & 0x1) << (newpos-1)
    end
    return out
end

@inline bit_match(config::UInt64, mask::UInt64, pattern::UInt64) = (config & mask) == pattern

function _build_axismap(output_vars::Vector{Int})
    isempty(output_vars) && return Int[]
    max_var = maximum(output_vars)
    axismap = zeros(Int, max_var)
    @inbounds for (idx, var_id) in enumerate(output_vars)
        axismap[var_id] = idx
    end
    return axismap
end

function extract_inner_configs(contracted::AbstractArray{T, N}, n_inner::Int) where {T, N}
    @assert n_inner == N
    configs = Vector{UInt64}()
    one_tropical = one(Tropical{Float64})
    
    @inbounds for lin in eachindex(contracted)
        if contracted[lin] == one_tropical
            linear_idx = LinearIndices(contracted)[lin] - 1
            config_bits = UInt64(linear_idx)
            push!(configs, config_bits)
        end
    end
    return configs
end

function combine_configs(boundary_bits::UInt64, inner_configs::Vector{UInt64}, n_boundary::Int)
    n_configs = length(inner_configs)
    full_configs = Vector{UInt64}(undef, n_configs)
    
    @inbounds for i in 1:n_configs
        full_configs[i] = boundary_bits | (inner_configs[i] << n_boundary)
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
        return BranchingTable(n_inner, [free_inner_configs])
    else
        return BranchingTable(0, [UInt64[]])
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
    stats = problem.ws.branch_stats
    has_detailed = !isnothing(stats) && !isnothing(stats.detailed)
    filtering_start_time = has_detailed ? time_ns() : 0
    
    var_ids = vcat(region.boundary_vars, region.inner_vars)
    n_vars = length(var_ids)

    fixed_positions = Tuple{Int, Bool}[]
    unfixed_positions = Int[]

    @inbounds for (i, var_id) in enumerate(var_ids)
        if is_fixed(problem.doms[var_id])
            required_value = has1(problem.doms[var_id])
            push!(fixed_positions, (i, required_value))
        else
            push!(unfixed_positions, i)
        end
    end

    if isempty(fixed_positions)
        if has_detailed
            filtering_time = (time_ns() - filtering_start_time) / 1e9
            record_filtering_time!(stats, filtering_time)
        end
        return table, var_ids
    end

    n_unfixed = length(unfixed_positions)

    mask::UInt64 = 0x0
    pattern::UInt64 = 0x0
    @inbounds for (pos, val) in fixed_positions
        pos_mask = UInt64(1) << (pos - 1)
        mask |= pos_mask
        if val
            pattern |= pos_mask
        end
    end

    filtered_table = similar(table.table, 0)
    sizehint!(filtered_table, length(table.table))

    @inbounds for config_group in table.table
        filtered_group = similar(config_group, 0)
        sizehint!(filtered_group, length(config_group))

        for config_bits in config_group
            if bit_match(UInt64(config_bits), mask, pattern)
                new_config = bit_extract(UInt64(config_bits), unfixed_positions)
                push!(filtered_group, typeof(config_bits)(new_config))
            end
        end

        if !isempty(filtered_group)
            push!(filtered_table, filtered_group)
        end
    end

    if has_detailed
        filtering_time = (time_ns() - filtering_start_time) / 1e9
        record_filtering_time!(stats, filtering_time)
    end

    isempty(filtered_table) && return BranchingTable(0, eltype(table.table)[]), Int[]
    
    unfixed_var_ids = [var_ids[i] for i in unfixed_positions]
    
    @debug "filter_branching_table: Region has $(n_unfixed) unfixed variables"
    
    return BranchingTable(n_unfixed, filtered_table), unfixed_var_ids
end

function OptimalBranchingCore.branching_table(problem::TNProblem, solver::TNContractionSolver, variable::Int)
    stats = problem.ws.branch_stats
    
    cached_region, cached_table = get_cached_region(variable)
    if !isnothing(cached_region) && !isnothing(cached_table)
        record_cache_hit!(stats)
        filtered_table, unfixed_vars = filter_branching_table(cached_region, cached_table, problem)
        return filtered_table, unfixed_vars
    end

    record_cache_miss!(stats)
    region = create_region(problem, variable, solver)
    n_boundary = length(region.boundary_vars)
    n_inner = length(region.inner_vars)
    n_total = n_boundary + n_inner
    
    # Contract with all-unfixed doms for consistent caching
    all_unfixed_doms = fill(DM_BOTH, length(problem.doms))
    
    stats = problem.ws.branch_stats
    contraction_start_time = time_ns()

    contracted_tensor, output_vars = contract_region(problem.static, region, all_unfixed_doms)

    contraction_time = (time_ns() - contraction_start_time) / 1e9
    record_contraction_time!(stats, contraction_time)

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
        cache_region!(region, table)
        filtered_table, unfixed_vars = filter_branching_table(region, table, problem)
        return filtered_table, unfixed_vars
    end
    
    free_boundary_vars = region.boundary_vars
    n_free_boundary = length(free_boundary_vars)
    
    valid_config_groups = Vector{Vector{UInt64}}()
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
        
        boundary_bits = UInt64(free_config)
        full_configs = combine_configs(boundary_bits, free_inner_configs, n_boundary)
        
        push!(valid_config_groups, full_configs)
    end
    
    if isempty(valid_config_groups)
        table = BranchingTable(0, [UInt64[]])
        cache_region!(region, table)
        return table, Int[]
    end
    
    table = BranchingTable(n_total, valid_config_groups)
    cache_region!(region, table)

    filtered_table, unfixed_vars = filter_branching_table(region, table, problem)
    return filtered_table, unfixed_vars
end

# Constructor for MinGammaSelector (defined here after TNContractionSolver is available)
MinGammaSelector() = MinGammaSelector(TNContractionSolver(2,5), OptimalBranchingCore.GreedyMerge())
