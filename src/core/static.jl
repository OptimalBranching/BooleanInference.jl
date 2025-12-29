struct Variable
    deg::Int
end

function Base.show(io::IO, v::Variable)
    print(io, "Variable(deg=$(v.deg))")
end

struct BoolTensor
    var_axes::Vector{Int}
    tensor_data_idx::Int
end

function Base.show(io::IO, f::BoolTensor)
    print(io, "BoolTensor(vars=[$(join(f.var_axes, ", "))], data_idx=$(f.tensor_data_idx))")
end

struct ClauseTensor
    vars::Vector{Int}
    polarity::Vector{Bool}  # true = positive literal, false = negated
end

function ClauseTensor(lits::AbstractVector{<:Integer})
    vars = Vector{Int}(undef, length(lits))
    polarity = Vector{Bool}(undef, length(lits))
    @inbounds for i in eachindex(lits)
        lit = Int(lits[i])
        @assert lit != 0 "ClauseTensor literal cannot be 0"
        vars[i] = abs(lit)
        polarity[i] = lit > 0
    end
    return ClauseTensor(vars, polarity)
end

function Base.show(io::IO, c::ClauseTensor)
    print(io, "ClauseTensor(vars=[$(join(c.vars, ", "))], polarity=$(c.polarity))")
end

# Shared tensor data (flyweight pattern for deduplication)
struct TensorData
    dense_tensor::BitVector     # For contraction operations: satisfied_configs[config+1] = true
    support::Vector{UInt16}     # For propagation: list of satisfied configs (0-indexed)
    support_or::UInt16          # OR over support (for fast m==0 scan)
    support_and::UInt16         # AND over support (for fast m==0 scan)
end

function Base.show(io::IO, td::TensorData)
    print(io, "TensorData(support=$(length(td.support))/$(length(td.dense_tensor)))")
end

# Extract sparse support from dense BitVector
function extract_supports(dense_tensor::BitVector)
    indices = findall(dense_tensor)
    supports = Vector{UInt16}(undef, length(indices))
    @inbounds for i in eachindex(indices)
        supports[i] = UInt16(indices[i] - 1)  # 0-indexed
    end
    return supports
end

# Constructor that automatically extracts support
function TensorData(dense_tensor::BitVector)
    @show dense_tensor
    support = extract_supports(dense_tensor)
    support_or = UInt16(0)
    support_and = UInt16(0xFFFF)
    @inbounds for i in eachindex(support)
        config = support[i]
        support_or |= config
        support_and &= config
    end
    return TensorData(dense_tensor, support, support_or, support_and)
end

# Constraint network representing the problem structure
struct ConstraintNetwork
    vars::Vector{Variable}
    unique_tensors::Vector{TensorData}
    tensors::Vector{BoolTensor}
    v2t::Vector{Vector{Int}}  # variable to tensor incidence
    orig_to_new::Vector{Int}  # original var id -> compressed var id (0 if removed)
end

function Base.show(io::IO, cn::ConstraintNetwork)
    print(io, "ConstraintNetwork(vars=$(length(cn.vars)), tensors=$(length(cn.tensors)), unique=$(length(cn.unique_tensors)))")
end

function Base.show(io::IO, ::MIME"text/plain", cn::ConstraintNetwork)
    println(io, "ConstraintNetwork:")
    println(io, "  variables: $(length(cn.vars))")
    println(io, "  tensors: $(length(cn.tensors))")
    println(io, "  unique tensor data: $(length(cn.unique_tensors))")
    println(io, "  variable-tensor incidence: $(length(cn.v2t))")
end

# Helper function to get tensor data from a tensor instance
@inline get_tensor_data(cn::ConstraintNetwork, tensor::BoolTensor) = cn.unique_tensors[tensor.tensor_data_idx]
@inline get_support(cn::ConstraintNetwork, tensor::BoolTensor) = get_tensor_data(cn, tensor).support
@inline get_support_or(cn::ConstraintNetwork, tensor::BoolTensor) = get_tensor_data(cn, tensor).support_or
@inline get_support_and(cn::ConstraintNetwork, tensor::BoolTensor) = get_tensor_data(cn, tensor).support_and
@inline get_dense_tensor(cn::ConstraintNetwork, tensor::BoolTensor) = get_tensor_data(cn, tensor).dense_tensor

function setup_problem(var_num::Int, tensors_to_vars::Vector{Vector{Int}}, tensor_data::Vector{BitVector}; precontract::Bool=true, protected_vars::Vector{Int}=Int[])
    F = length(tensors_to_vars)
    tensors = Vector{BoolTensor}(undef, F)
    vars_to_tensors = [Int[] for _ in 1:var_num]

    # Deduplicate tensor data: map BitVector to index in unique_tensors
    unique_data = TensorData[]
    data_to_idx = Dict{BitVector,Int}()

    @inbounds for i in 1:F
        var_axes = tensors_to_vars[i]
        @assert length(tensor_data[i]) == 1 << length(var_axes)

        # Find or create unique tensor data
        if haskey(data_to_idx, tensor_data[i])
            data_idx = data_to_idx[tensor_data[i]]
        else
            push!(unique_data, TensorData(tensor_data[i]))
            data_idx = length(unique_data)
            data_to_idx[tensor_data[i]] = data_idx
        end

        tensors[i] = BoolTensor(var_axes, data_idx)
        for v in var_axes
            push!(vars_to_tensors[v], i)
        end
    end

    # Pre-contract if enabled: iterate constant propagation, equivalent variable merging, and degree-2 contraction
    protected_set = Set(protected_vars)
    if precontract
        tensors, vars_to_tensors, unique_data, data_to_idx =
            precontract_all!(tensors, vars_to_tensors, unique_data, data_to_idx; protected_vars=protected_set)
    end

    tensors, vars_to_tensors, orig_to_new = compress_variables!(tensors, vars_to_tensors)

    vars = Vector{Variable}(undef, length(vars_to_tensors))
    for i in 1:length(vars_to_tensors)
        vars[i] = Variable(length(vars_to_tensors[i]))
    end
    return ConstraintNetwork(vars, unique_data, tensors, vars_to_tensors, orig_to_new)
end

function setup_from_csp(csp::ConstraintSatisfactionProblem; precontract::Bool=true, protected_vars::Vector{Int}=Int[])
    # Extract constraints directly
    cons = constraints(csp); var_num = num_variables(csp)
    # Build tensors directly from LocalConstraints
    tensors_to_vars = [c.variables for c in cons]
    tensor_data = [BitVector(c.specification) for c in cons]
    return setup_problem(var_num, tensors_to_vars, tensor_data; precontract, protected_vars)
end

"""
    contract_two_tensors(data1::BitVector, vars1::Vector{Int}, data2::BitVector, vars2::Vector{Int}, contract_var::Int) -> (BitVector, Vector{Int})

Contract two boolean tensors along a shared variable using Einstein summation.
Boolean contraction semantics: result[config] = ∃val. tensor1[config ∪ val] ∧ tensor2[config ∪ val]
Returns the contracted tensor data and its variable axes.
"""
function contract_two_tensors(data1::BitVector, vars1::Vector{Int}, data2::BitVector, vars2::Vector{Int}, contract_var::Int)
    # Convert BitVectors to multi-dimensional Int arrays (0/1)
    dims1 = ntuple(_ -> 2, length(vars1))
    dims2 = ntuple(_ -> 2, length(vars2))

    arr1 = reshape(Int.(data1), dims1)
    arr2 = reshape(Int.(data2), dims2)

    # Build output variable list (union minus the contracted variable)
    out_vars = Int[]
    for v in vars1
        v != contract_var && push!(out_vars, v)
    end
    for v in vars2
        v != contract_var && !(v in out_vars) && push!(out_vars, v)
    end

    # Use OMEinsum for tensor contraction
    # Boolean semantics: ∃ (OR over contracted indices) ∧ (AND pointwise)
    # In arithmetic: product for AND, sum for OR (∃), then check > 0
    eincode = OMEinsum.EinCode([vars1, vars2], out_vars)
    optcode = OMEinsum.optimize_code(eincode, OMEinsum.uniformsize(eincode, 2), OMEinsum.GreedyMethod())

    # Perform contraction: sum of products (at least one satisfying assignment exists)
    result_arr = optcode(arr1, arr2)

    # Convert back to BitVector: any positive value means satisfiable
    gt = result_arr .> 0
    if gt isa AbstractArray
        result = BitVector(vec(gt))
    else
        result = BitVector([gt])
    end

    return result, out_vars
end

"""
    precontract_all!(tensors, vars_to_tensors, unique_data, data_to_idx; protected_vars=Set{Int}())

Iterate constant propagation, equivalent variable merging, and degree-2 contraction until convergence.
Protected variables will not be eliminated during precontraction.
"""
function precontract_all!(tensors::Vector{BoolTensor}, vars_to_tensors::Vector{Vector{Int}}, unique_data::Vector{TensorData}, data_to_idx::Dict{BitVector,Int}; protected_vars::Set{Int}=Set{Int}())
    total_constants = 0
    total_equiv = 0
    total_degree2 = 0

    changed = true
    while changed
        changed = false

        # 1. Constant propagation (protected vars are still propagated but kept in the network)
        tensors, vars_to_tensors, unique_data, data_to_idx, n_const =
            precontract_constants!(tensors, vars_to_tensors, unique_data, data_to_idx; protected_vars=protected_vars)
        if n_const > 0
            total_constants += n_const
            changed = true
        end

        # 2. Equivalent variable merging (don't merge protected vars away)
        tensors, vars_to_tensors, unique_data, data_to_idx, n_equiv =
            precontract_equivalent_vars!(tensors, vars_to_tensors, unique_data, data_to_idx; protected_vars=protected_vars)
        if n_equiv > 0
            total_equiv += n_equiv
            changed = true
        end

        # 3. Degree-2 contraction (don't eliminate protected vars)
        tensors, vars_to_tensors, unique_data, data_to_idx, n_deg2 =
            precontract_degree2!(tensors, vars_to_tensors, unique_data, data_to_idx; protected_vars=protected_vars)
        if n_deg2 > 0
            total_degree2 += n_deg2
            changed = true
        end
    end

    if total_constants > 0 || total_equiv > 0 || total_degree2 > 0
        @info "Precontract: constants=$total_constants, equivalent_vars=$total_equiv, degree2=$total_degree2"
    end

    return tensors, vars_to_tensors, unique_data, data_to_idx
end

"""
    precontract_constants!(tensors, vars_to_tensors, unique_data, data_to_idx; protected_vars=Set{Int}())

If a tensor has only 1 satisfying configuration, fix all its variables and slice other tensors accordingly.
Protected variables are still propagated but kept in the network with unit tensors.
Returns the number of constants propagated.
"""
function precontract_constants!(tensors::Vector{BoolTensor}, vars_to_tensors::Vector{Vector{Int}}, unique_data::Vector{TensorData}, data_to_idx::Dict{BitVector,Int}; protected_vars::Set{Int}=Set{Int}())
    n_vars = length(vars_to_tensors)
    active_tensors = trues(length(tensors))
    fixed_vars = Dict{Int,Bool}()  # var_id => fixed_value
    propagated_count = 0

    # Find tensors with single configuration and extract variable assignments
    for (t_idx, tensor) in enumerate(tensors)
        active_tensors[t_idx] || continue
        td = unique_data[tensor.tensor_data_idx]

        if length(td.support) == 1
            # Skip tensors where ALL variables are protected - these are intentional unit tensors
            if all(v -> v in protected_vars, tensor.var_axes)
                continue
            end

            config = td.support[1]
            # Extract fixed values for all variables
            for (i, var_id) in enumerate(tensor.var_axes)
                val = ((config >> (i - 1)) & 1) == 1
                if haskey(fixed_vars, var_id)
                    # Conflict check
                    if fixed_vars[var_id] != val
                        error("Conflict: variable $var_id has conflicting fixed values")
                    end
                else
                    fixed_vars[var_id] = val
                    propagated_count += 1
                end
            end
            active_tensors[t_idx] = false
        elseif length(td.support) == 0
            error("Unsatisfiable: tensor has no valid configurations")
        end
    end

    isempty(fixed_vars) && return tensors, vars_to_tensors, unique_data, data_to_idx, 0

    # Slice all tensors that reference fixed variables
    for (t_idx, tensor) in enumerate(tensors)
        active_tensors[t_idx] || continue

        # Check if this tensor has any fixed variables
        has_fixed = any(v -> haskey(fixed_vars, v), tensor.var_axes)
        has_fixed || continue

        # Build slicing masks
        old_data = unique_data[tensor.tensor_data_idx].dense_tensor
        old_vars = tensor.var_axes
        new_vars = Int[]

        # Calculate which configs to keep based on fixed variables
        fixed_mask = UInt16(0)
        fixed_value = UInt16(0)
        for (i, var_id) in enumerate(old_vars)
            if haskey(fixed_vars, var_id)
                bit = UInt16(1) << (i - 1)
                fixed_mask |= bit
                if fixed_vars[var_id]
                    fixed_value |= bit
                end
            else
                push!(new_vars, var_id)
            end
        end

        # Create sliced tensor data
        if isempty(new_vars)
            # All variables fixed - check if satisfied
            if !old_data[fixed_value+1]
                error("Unsatisfiable: fixed assignment violates tensor constraint")
            end
            active_tensors[t_idx] = false
        else
            new_size = 1 << length(new_vars)
            new_data = falses(new_size)

            # Map old configs to new configs
            for old_config in 0:(length(old_data)-1)
                old_data[old_config+1] || continue

                # Check if matches fixed values
                (UInt16(old_config) & fixed_mask) == fixed_value || continue

                # Compute new config by extracting unfixed bits
                new_config = 0
                new_bit_pos = 0
                for (i, var_id) in enumerate(old_vars)
                    if !haskey(fixed_vars, var_id)
                        if ((old_config >> (i - 1)) & 1) == 1
                            new_config |= (1 << new_bit_pos)
                        end
                        new_bit_pos += 1
                    end
                end
                new_data[new_config+1] = true
            end

            # Find or create new tensor data
            if haskey(data_to_idx, new_data)
                new_data_idx = data_to_idx[new_data]
            else
                push!(unique_data, TensorData(new_data))
                new_data_idx = length(unique_data)
                data_to_idx[new_data] = new_data_idx
            end

            tensors[t_idx] = BoolTensor(new_vars, new_data_idx)
        end
    end

    # Update vars_to_tensors: remove fixed variables and update indices
    for var_id in keys(fixed_vars)
        vars_to_tensors[var_id] = Int[]
    end

    for (t_idx, tensor) in enumerate(tensors)
        active_tensors[t_idx] || continue
        for v in tensor.var_axes
            if t_idx ∉ vars_to_tensors[v]
                push!(vars_to_tensors[v], t_idx)
            end
        end
    end

    # Rebuild vars_to_tensors from scratch for active tensors
    for v in 1:n_vars
        haskey(fixed_vars, v) && continue
        vars_to_tensors[v] = Int[]
    end
    for (t_idx, tensor) in enumerate(tensors)
        active_tensors[t_idx] || continue
        for v in tensor.var_axes
            push!(vars_to_tensors[v], t_idx)
        end
    end

    # Compact tensors
    active_indices = findall(active_tensors)
    new_tensors = tensors[active_indices]

    idx_map = Dict{Int,Int}()
    for (new_idx, old_idx) in enumerate(active_indices)
        idx_map[old_idx] = new_idx
    end

    new_vars_to_tensors = [Int[] for _ in 1:n_vars]
    for (var_id, tensor_list) in enumerate(vars_to_tensors)
        for old_t_idx in tensor_list
            if haskey(idx_map, old_t_idx)
                push!(new_vars_to_tensors[var_id], idx_map[old_t_idx])
            end
        end
    end

    # For protected variables that were fixed, add unit tensors to keep them in the network
    for var_id in protected_vars
        if haskey(fixed_vars, var_id) && isempty(new_vars_to_tensors[var_id])
            # Create unit tensor: [false, true] or [true, false] depending on fixed value
            unit_data = fixed_vars[var_id] ? BitVector([false, true]) : BitVector([true, false])
            if haskey(data_to_idx, unit_data)
                data_idx = data_to_idx[unit_data]
            else
                push!(unique_data, TensorData(unit_data))
                data_idx = length(unique_data)
                data_to_idx[unit_data] = data_idx
            end
            new_tensor = BoolTensor([var_id], data_idx)
            push!(new_tensors, new_tensor)
            push!(new_vars_to_tensors[var_id], length(new_tensors))
        end
    end

    return new_tensors, new_vars_to_tensors, unique_data, data_to_idx, propagated_count
end

"""
    precontract_equivalent_vars!(tensors, vars_to_tensors, unique_data, data_to_idx; protected_vars=Set{Int}())

Detect equivalent variable pairs (EQ pattern [1,0,0,1]) and merge v2 into v1.
Protected variables are always kept as representatives (never merged away).
Returns the number of merged variable pairs.
"""
function precontract_equivalent_vars!(tensors::Vector{BoolTensor}, vars_to_tensors::Vector{Vector{Int}}, unique_data::Vector{TensorData}, data_to_idx::Dict{BitVector,Int}; protected_vars::Set{Int}=Set{Int}())
    n_vars = length(vars_to_tensors)
    active_tensors = trues(length(tensors))
    var_merged_to = collect(1:n_vars)  # Union-find: var_merged_to[v] = representative of v
    merged_count = 0

    # EQ pattern: support = {0b00, 0b11} = {0, 3}
    eq_pattern = Set{UInt16}([0, 3])

    # Find EQ tensors
    for (t_idx, tensor) in enumerate(tensors)
        length(tensor.var_axes) == 2 || continue
        td = unique_data[tensor.tensor_data_idx]

        if Set(td.support) == eq_pattern
            v1, v2 = tensor.var_axes[1], tensor.var_axes[2]

            # Find representatives
            while var_merged_to[v1] != v1
                v1 = var_merged_to[v1]
            end
            while var_merged_to[v2] != v2
                v2 = var_merged_to[v2]
            end

            if v1 != v2
                # Merge v2 into v1, but protected variables should stay as representatives
                # Priority: protected > smaller id
                v1_protected = v1 in protected_vars
                v2_protected = v2 in protected_vars

                if v2_protected && !v1_protected
                    # Swap so protected var (v2) becomes representative
                    v1, v2 = v2, v1
                elseif !v1_protected && !v2_protected && v1 > v2
                    # Neither protected, use smaller id as representative
                    v1, v2 = v2, v1
                elseif v1_protected && v2_protected
                    # Both protected - keep both, don't merge
                    continue
                end
                # Now merge v2 into v1 (v1 is the representative)
                var_merged_to[v2] = v1
                merged_count += 1
            end

            # Mark EQ tensor for removal
            active_tensors[t_idx] = false
        end
    end

    merged_count == 0 && return tensors, vars_to_tensors, unique_data, data_to_idx, 0

    # Path compression for union-find
    for v in 1:n_vars
        root = v
        while var_merged_to[root] != root
            root = var_merged_to[root]
        end
        # Path compression
        curr = v
        while var_merged_to[curr] != root
            next = var_merged_to[curr]
            var_merged_to[curr] = root
            curr = next
        end
    end

    # Replace merged variables in all tensors
    for (t_idx, tensor) in enumerate(tensors)
        active_tensors[t_idx] || continue

        old_vars = tensor.var_axes
        new_vars = [var_merged_to[v] for v in old_vars]

        # Check for duplicate variables after merging
        if length(unique(new_vars)) < length(new_vars)
            # Need to contract diagonal
            old_data = unique_data[tensor.tensor_data_idx].dense_tensor

            # Find unique vars and their positions
            seen = Dict{Int,Int}()
            dedup_vars = Int[]
            var_mapping = Int[]  # old position -> position in dedup_vars

            for (i, v) in enumerate(new_vars)
                if haskey(seen, v)
                    push!(var_mapping, seen[v])
                else
                    push!(dedup_vars, v)
                    seen[v] = length(dedup_vars)
                    push!(var_mapping, length(dedup_vars))
                end
            end

            # Create contracted tensor: only keep configs where merged vars agree
            new_size = 1 << length(dedup_vars)
            new_data = falses(new_size)

            for old_config in 0:(length(old_data)-1)
                old_data[old_config+1] || continue

                # Check if all merged positions have same value
                valid = true
                new_config = 0
                dedup_vals = fill(-1, length(dedup_vars))

                for (i, dedup_pos) in enumerate(var_mapping)
                    bit_val = (old_config >> (i - 1)) & 1
                    if dedup_vals[dedup_pos] == -1
                        dedup_vals[dedup_pos] = bit_val
                    elseif dedup_vals[dedup_pos] != bit_val
                        valid = false
                        break
                    end
                end

                if valid
                    for (i, val) in enumerate(dedup_vals)
                        if val == 1
                            new_config |= (1 << (i - 1))
                        end
                    end
                    new_data[new_config+1] = true
                end
            end

            # Find or create new tensor data
            if haskey(data_to_idx, new_data)
                new_data_idx = data_to_idx[new_data]
            else
                push!(unique_data, TensorData(new_data))
                new_data_idx = length(unique_data)
                data_to_idx[new_data] = new_data_idx
            end

            tensors[t_idx] = BoolTensor(dedup_vars, new_data_idx)
        elseif new_vars != old_vars
            tensors[t_idx] = BoolTensor(new_vars, tensor.tensor_data_idx)
        end
    end

    # Compact tensors
    active_indices = findall(active_tensors)
    new_tensors = tensors[active_indices]

    idx_map = Dict{Int,Int}()
    for (new_idx, old_idx) in enumerate(active_indices)
        idx_map[old_idx] = new_idx
    end

    # Rebuild vars_to_tensors
    new_vars_to_tensors = [Int[] for _ in 1:n_vars]
    for (new_t_idx, tensor) in enumerate(new_tensors)
        for v in tensor.var_axes
            push!(new_vars_to_tensors[v], new_t_idx)
        end
    end

    return new_tensors, new_vars_to_tensors, unique_data, data_to_idx, merged_count
end

function precontract_degree2!(tensors::Vector{BoolTensor}, vars_to_tensors::Vector{Vector{Int}}, unique_data::Vector{TensorData}, data_to_idx::Dict{BitVector,Int}; protected_vars::Set{Int}=Set{Int}())
    n_vars = length(vars_to_tensors)
    active_tensors = trues(length(tensors))  # Track which tensors are still active
    contracted_count = 0

    # Iterate until no more degree-2 variables can be contracted
    changed = true
    while changed
        changed = false

        # Find degree-2 variables (but not protected ones)
        for var_id in 1:n_vars
            # Skip protected variables - they should not be contracted away
            var_id in protected_vars && continue

            tensor_list = vars_to_tensors[var_id]

            # Filter to only active tensors
            active_list = filter(t -> active_tensors[t], tensor_list)

            if length(active_list) == 2
                t1_idx, t2_idx = active_list
                t1 = tensors[t1_idx]
                t2 = tensors[t2_idx]

                # Get tensor data
                data1 = unique_data[t1.tensor_data_idx].dense_tensor
                data2 = unique_data[t2.tensor_data_idx].dense_tensor

                # Contract the two tensors
                new_data, new_vars = contract_two_tensors(data1, t1.var_axes, data2, t2.var_axes, var_id)

                # Find or create unique tensor data for the contracted result
                if haskey(data_to_idx, new_data)
                    new_data_idx = data_to_idx[new_data]
                else
                    push!(unique_data, TensorData(new_data))
                    new_data_idx = length(unique_data)
                    data_to_idx[new_data] = new_data_idx
                end

                # Create new contracted tensor (reuse one of the slots)
                new_tensor = BoolTensor(new_vars, new_data_idx)
                tensors[t1_idx] = new_tensor

                # Mark second tensor as inactive
                active_tensors[t2_idx] = false

                # Update vars_to_tensors mapping
                # Remove old references
                for v in t1.var_axes
                    filter!(t -> t != t1_idx, vars_to_tensors[v])
                end
                for v in t2.var_axes
                    filter!(t -> t != t2_idx, vars_to_tensors[v])
                end

                # Add new references
                for v in new_vars
                    push!(vars_to_tensors[v], t1_idx)
                end

                contracted_count += 1
                changed = true
                break  # Restart the search after each contraction
            end
        end
    end

    # Compact the tensor list by removing inactive tensors
    active_indices = findall(active_tensors)
    new_tensors = tensors[active_indices]

    # Build index mapping: old_idx -> new_idx
    idx_map = Dict{Int,Int}()
    for (new_idx, old_idx) in enumerate(active_indices)
        idx_map[old_idx] = new_idx
    end

    # Update vars_to_tensors with new indices
    new_vars_to_tensors = [Int[] for _ in 1:n_vars]
    for (var_id, tensor_list) in enumerate(vars_to_tensors)
        for old_t_idx in tensor_list
            if haskey(idx_map, old_t_idx)
                push!(new_vars_to_tensors[var_id], idx_map[old_t_idx])
            end
        end
    end

    return new_tensors, new_vars_to_tensors, unique_data, data_to_idx, contracted_count
end

function compress_variables!(tensors::Vector{BoolTensor}, vars_to_tensors::Vector{Vector{Int}})
    n_vars = length(vars_to_tensors)
    orig_to_new = zeros(Int, n_vars)
    next_id = 0
    for i in 1:n_vars
        if !isempty(vars_to_tensors[i])
            next_id += 1
            orig_to_new[i] = next_id
        end
    end

    @inbounds for t in tensors
        for i in eachindex(t.var_axes)
            t.var_axes[i] = orig_to_new[t.var_axes[i]]
        end
    end

    new_vars_to_tensors = [Int[] for _ in 1:next_id]
    @inbounds for (tid, t) in enumerate(tensors)
        for v in t.var_axes
            push!(new_vars_to_tensors[v], tid)
        end
    end

    return tensors, new_vars_to_tensors, orig_to_new
end
