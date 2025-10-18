using OptimalBranchingCore: BranchingTable

struct TNContractionSolver <: AbstractTableSolver end

function separate_fixed_free_boundary(region::Region, doms::Vector{DomainMask})
    fixed_vars = Int[]
    fixed_vals = Int[]
    free_vars = Int[]
    free_indices = Int[]
    
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


function construct_boundary_config(region::Region, doms::Vector{DomainMask}, free_boundary_indices::Vector{Int}, free_config::Int)
    n_boundary = length(region.boundary_vars)
    boundary_config = Vector{Bool}(undef, n_boundary)
    
    @inbounds for i in 1:n_boundary
        var_id = region.boundary_vars[i]
        if is_fixed(doms[var_id])
            # Use the fixed value
            boundary_config[i] = has1(doms[var_id])
        else
            # Use the enumerated value
            j = findfirst(==(i), free_boundary_indices)
            bit = (free_config >> (j-1)) & 0x1
            boundary_config[i] = (bit == 1)
        end
    end
    
    return boundary_config
end

function construct_inner_config(region::Region, doms::Vector{DomainMask}, inner_var_ids::Vector{Int},free_inner_configs::Vector{Vector{Bool}})
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
                j = findfirst(==(var_id), inner_var_ids)
                inner_config[i] = free_inner_configs[config_idx][j]
            end
        end
        inner_configs[config_idx] = inner_config
    end
    
    return inner_configs
end


function extract_inner_configs(contracted::Array{T, N}, n_inner::Int) where {T, N}
    # Find all feasible configurations (where value == 1)
    @assert n_inner == N
    feasible_indices = findall(x -> x == one(Tropical{Float64}), contracted)
    n_configs = length(feasible_indices)
    configs = Vector{Vector{Bool}}(undef, n_configs)
    
    @inbounds for (config_idx, idx) in enumerate(feasible_indices)
        config = Vector{Bool}(undef, n_inner)
        if n_inner > 0
            linear_idx = LinearIndices(contracted)[idx] - 1  # 0-based
            for i in 1:n_inner
                config[i] = ((linear_idx >> (i-1)) & 0x1) == 1
            end
        end
        configs[config_idx] = config
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
        inner_config = inner_configs[i]
        full_config = Vector{Bool}(undef, n_total)
        
        # Copy boundary config
        for j in 1:n_boundary
            full_config[j] = boundary_config[j]
        end
        
        # Copy inner config
        for j in 1:n_inner
            full_config[n_boundary + j] = inner_config[j]
        end
        
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
    axis_lookup::Dict{Int,Int},
)
    isempty(assignments) && return tensor
    nd = ndims(tensor)
    nd == 0 && return tensor

    selectors = Vector{Any}(undef, nd)
    for i in 1:nd
        selectors[i] = Colon()
    end

    for (var_id, value) in assignments
        axis = get(axis_lookup, var_id, nothing)
        @assert axis !== nothing "Boundary variable $var_id not found in contraction axes"
        selectors[axis] = value ? 2 : 1
    end

    view_tensor = view(tensor, selectors...)
    return copy(view_tensor)
end

function handle_no_boundary_case(
    problem::TNProblem,
    region::Region,
    contracted::AbstractArray{Tropical{Float64}},
    inner_var_ids::Vector{Int},
)
    n_inner = length(region.inner_vars)
    
    free_inner_configs = extract_inner_configs(contracted, length(inner_var_ids))
    
    if !isempty(free_inner_configs)
        inner_configs = construct_inner_config(
            region, problem.doms, inner_var_ids, free_inner_configs
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
    # Step 1: Get region
    region = get_cached_region(problem)
    isnothing(region) && error("No cached region found. Make sure `select_variables` is called first.")
    
    n_boundary = length(region.boundary_vars)
    n_inner = length(region.inner_vars)
    n_total = n_boundary + n_inner
    @assert n_total == length(variables)
    
    contracted_tensor, output_vars = get_region_contraction(problem, region)

    axis_lookup = Dict{Int,Int}()
    @inbounds for (idx, var_id) in enumerate(output_vars)
        axis_lookup[var_id] = idx
    end

    inner_output_vars = Int[]
    @inbounds for var_id in output_vars
        if var_id in region.inner_vars
            push!(inner_output_vars, var_id)
        end
    end

    # Step 2: Handle special case - no boundary variables
    if n_boundary == 0
        return handle_no_boundary_case(problem, region, contracted_tensor, inner_output_vars)
    end
    
    # Step 3: Separate fixed and free boundary variables
    _, _, free_boundary_vars, free_boundary_indices = 
        separate_fixed_free_boundary(region, problem.doms)
    
    n_free_boundary = length(free_boundary_vars)
    
    # Step 4: Enumerate free boundary configurations
    valid_config_groups = Vector{Vector{Bool}}[]
    
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
            axis_lookup,
        )
        
        # Extract feasible inner configurations
        free_inner_configs = extract_inner_configs(contracted_slice, length(inner_output_vars))
        
        isempty(free_inner_configs) && continue
        
        # Construct full boundary configuration
        boundary_config = construct_boundary_config(region, problem.doms, free_boundary_indices, free_config)

        inner_configs = construct_inner_config(region, problem.doms, inner_output_vars, free_inner_configs)
         
        full_configs = combine_configs(boundary_config, inner_configs)
        
        push!(valid_config_groups, full_configs)
    end
    
    # Step 5: Return branching table
    if isempty(valid_config_groups)
        return BranchingTable(0, [Int[]])
    end
    
    return BranchingTable(n_total, valid_config_groups)
end
