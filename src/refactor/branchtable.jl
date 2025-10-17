using OptimalBranchingCore: BranchingTable

struct TNContractionSolver <: AbstractTableSolver end

# =======================================================
# Helper functions for branching table construction
# =======================================================

function separate_fixed_free_boundary(region::Region, doms::Vector{DomainMask})
    fixed_vars = Int32[]
    fixed_vals = Int32[]
    free_vars = Int32[]
    free_indices = Int[]
    
    for (i, var_id) in enumerate(region.boundary_vars)
        if is_fixed(doms[var_id.id])
            push!(fixed_vars, var_id.id)
            push!(fixed_vals, has1(doms[var_id.id]) ? Int32(1) : Int32(0))
        else
            push!(free_vars, var_id.id)
            push!(free_indices, i)
        end
    end
    
    return fixed_vars, fixed_vals, free_vars, free_indices
end


function construct_boundary_config(
    region::Region, 
    doms::Vector{DomainMask},
    free_boundary_indices::Vector{Int},
    free_config::Int
)
    n_boundary = length(region.boundary_vars)
    boundary_config = Vector{Bool}(undef, n_boundary)
    
    for i in 1:n_boundary
        var_id = region.boundary_vars[i]
        if is_fixed(doms[var_id.id])
            # Use the fixed value
            boundary_config[i] = has1(doms[var_id.id])
        else
            # Use the enumerated value
            j = findfirst(==(i), free_boundary_indices)
            bit = (free_config >> (j-1)) & 0x1
            boundary_config[i] = (bit == 1)
        end
    end
    
    return boundary_config
end

function construct_inner_config(
    region::Region, 
    doms::Vector{DomainMask},
    inner_var_ids::Vector{Int32},
    free_inner_configs::Vector{Vector{Bool}}
)
    n_inner = length(region.inner_vars)
    n_config = length(free_inner_configs)
    inner_configs = Vector{Vector{Bool}}(undef, n_config)

    for config_idx in 1:n_config
        inner_config = Vector{Bool}(undef, n_inner)
        for i in 1:n_inner
            var_id = region.inner_vars[i].id
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
    configs = Vector{Bool}[]
    for idx in feasible_indices
        config = Bool[]
        if n_inner > 0
            linear_idx = LinearIndices(contracted)[idx] - 1  # 0-based
            for i in 1:n_inner
                push!(config, ((linear_idx >> (i-1)) & 0x1) == 1)
            end
        end
        push!(configs, config)
    end
    return configs
end

function combine_configs(boundary_config::Vector{Bool}, inner_configs::Vector{Vector{Bool}})
    full_configs = Vector{Bool}[]
    
    for inner_config in inner_configs
        full_config = vcat(boundary_config, inner_config)
        push!(full_configs, full_config)
    end
    
    return full_configs
end


function handle_no_boundary_case(problem::TNProblem, region::Region)
    n_inner = length(region.inner_vars)
    
    contracted, inner_var_ids = contract_region(problem.static, region, problem.doms)
    
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

# ======================================================
# Main branching table function
# ======================================================

function OptimalBranchingCore.branching_table(
    problem::TNProblem, 
    solver::TNContractionSolver, 
    variables::Vector{T}
) where T
    # Step 1: Get cached region
    region = get_cached_region(problem)
    if isnothing(region)
        error("No cached region found. Make sure `select_variables` is called first.")
    end
    
    n_boundary = length(region.boundary_vars)
    n_inner = length(region.inner_vars)
    n_total = n_boundary + n_inner
    @assert n_total == length(variables)
    
    # Step 2: Handle special case - no boundary variables
    if n_boundary == 0
        return handle_no_boundary_case(problem, region)
    end
    
    # Step 3: Separate fixed and free boundary variables
    _, _, free_boundary_vars, free_boundary_indices = 
        separate_fixed_free_boundary(region, problem.doms)
    
    n_free_boundary = length(free_boundary_vars)
    
    # Step 4: Enumerate free boundary configurations
    valid_config_groups = Vector{Vector{Bool}}[]
    
    for free_config in 0:(2^n_free_boundary - 1)
        # Fix free boundary variables in temporary doms
        doms_temp = copy(problem.doms)
        for (j, var_id) in enumerate(free_boundary_vars)
            bit = (free_config >> (j-1)) & 0x1
            doms_temp[var_id] = (bit == 1) ? DM_1 : DM_0
        end
        
        # Contract tensors (all boundary vars now fixed)
        contracted, inner_var_ids = contract_region(problem.static, region, doms_temp)
        
        # Extract feasible inner configurations
        free_inner_configs = extract_inner_configs(contracted, length(inner_var_ids))
        
        isempty(free_inner_configs) && continue
        
        # Construct full boundary configuration
        boundary_config = construct_boundary_config(
            region, problem.doms, free_boundary_indices, free_config
        )

        inner_configs = construct_inner_config(
             region, problem.doms, inner_var_ids, free_inner_configs
        )
         
        full_configs = combine_configs(boundary_config, inner_configs)
        
        push!(valid_config_groups, full_configs)
    end
    
    # Step 5: Return branching table
    if isempty(valid_config_groups)
        return BranchingTable(0, [Int[]])
    end
    
    return BranchingTable(n_total, valid_config_groups)
end
