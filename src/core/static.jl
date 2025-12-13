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

# Shared tensor data (flyweight pattern for deduplication)
struct TensorData
    dense_tensor::BitVector     # For contraction operations: satisfied_configs[config+1] = true
    support::Vector{UInt16}     # For propagation: list of satisfied configs (0-indexed)
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
    return TensorData(dense_tensor, support)
end

# Constraint network representing the problem structure
struct ConstraintNetwork
    vars::Vector{Variable}
    unique_tensors::Vector{TensorData}
    tensors::Vector{BoolTensor}
    v2t::Vector{Vector{Int}}  # variable to tensor incidence
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
@inline get_dense_tensor(cn::ConstraintNetwork, tensor::BoolTensor) = get_tensor_data(cn, tensor).dense_tensor

function setup_problem(var_num::Int, tensors_to_vars::Vector{Vector{Int}}, tensor_data::Vector{BitVector})
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

    vars = Vector{Variable}(undef, var_num)
    for i in 1:var_num
        vars[i] = Variable(length(vars_to_tensors[i]))
    end
    return ConstraintNetwork(vars, unique_data, tensors, vars_to_tensors)
end


function setup_from_csp(csp::ConstraintSatisfactionProblem; simplify::Bool=false, support_limit::Int=128)
    # Extract constraints directly
    cons = constraints(csp)
    var_num = num_variables(csp)

    # Build tensors directly from LocalConstraints
    tensors_to_vars = [c.variables for c in cons]
    tensor_data = [BitVector(c.specification) for c in cons]

    # Simplify tensor network before creating ConstraintNetwork
    if simplify
        tensors_to_vars, tensor_data = simplify_tensor_network(
            var_num, tensors_to_vars, tensor_data; 
            support_limit=support_limit
        )
        @show length(tensors_to_vars)
    end

    return setup_problem(var_num, tensors_to_vars, tensor_data)
end

# function setup_from_tensor_network(tn)
#     t2v = getixsv(tn.code)
#     tensors = GenericTensorNetworks.generate_tensors(1, tn)

#     # Convert to sparse representation directly
#     sparse_tensors = [UInt16[UInt16(idx - 1) for (idx, x) in enumerate(vec(t)) if x == 1] for t in tensors]
    
#     # Create BipartiteGraph
#     F = length(t2v)
#     bool_tensors = Vector{BoolTensor}(undef, F)
#     var_num = length(tn.problem.symbols)
#     vars_to_tensors = [Int[] for _ in 1:var_num]
    
#     @inbounds for i in 1:F
#         var_axes = t2v[i]
#         bool_tensors[i] = BoolTensor(var_axes, sparse_tensors[i])
#         for v in var_axes
#             push!(vars_to_tensors[v], i)
#         end
#     end

#     vars = Vector{Variable}(undef, var_num)
#     for i in 1:var_num
#         vars[i] = Variable(length(vars_to_tensors[i]))
#     end
#     return BipartiteGraph(vars, bool_tensors, vars_to_tensors)
# end