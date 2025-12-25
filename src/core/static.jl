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

function setup_problem(var_num::Int, tensors_to_vars::Vector{Vector{Int}}, tensor_data::Vector{BitVector}; precontract::Bool=true)
    F = length(tensors_to_vars)
    tensors = Vector{BoolTensor}(undef, F)
    vars_to_tensors = [Int[] for _ in 1:var_num]

    # Deduplicate tensor data: map BitVector to index in unique_tensors
    unique_data = TensorData[]
    data_to_idx = Dict{BitVector, Int}()

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

    # Pre-contract degree-2 variables if enabled
    if precontract
        tensors, vars_to_tensors, unique_data, data_to_idx = 
            precontract_degree2!(tensors, vars_to_tensors, unique_data, data_to_idx)
    end

    tensors, vars_to_tensors, orig_to_new = compress_variables!(tensors, vars_to_tensors)

    vars = Vector{Variable}(undef, length(vars_to_tensors))
    for i in 1:length(vars_to_tensors)
        vars[i] = Variable(length(vars_to_tensors[i]))
    end
    return ConstraintNetwork(vars, unique_data, tensors, vars_to_tensors, orig_to_new)
end

function setup_from_csp(csp::ConstraintSatisfactionProblem; precontract::Bool=true)
    # Extract constraints directly
    cons = constraints(csp)
    var_num = num_variables(csp)

    # Build tensors directly from LocalConstraints
    tensors_to_vars = [c.variables for c in cons]
    tensor_data = [BitVector(c.specification) for c in cons]

    return setup_problem(var_num, tensors_to_vars, tensor_data; precontract=precontract)
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


function precontract_degree2!(tensors::Vector{BoolTensor}, vars_to_tensors::Vector{Vector{Int}}, unique_data::Vector{TensorData}, data_to_idx::Dict{BitVector, Int})
    n_vars = length(vars_to_tensors)
    active_tensors = trues(length(tensors))  # Track which tensors are still active
    contracted_count = 0
    
    # Iterate until no more degree-2 variables can be contracted
    changed = true
    while changed
        changed = false
        
        # Find degree-2 variables
        for var_id in 1:n_vars
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
    idx_map = Dict{Int, Int}()
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
    
    if contracted_count > 0
        @info "Pre-contracted $contracted_count degree-2 variables, reducing tensors from $(length(tensors)) to $(length(new_tensors))"
    end
    
    return new_tensors, new_vars_to_tensors, unique_data, data_to_idx
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
