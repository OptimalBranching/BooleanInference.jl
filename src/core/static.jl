struct TNStatic
    vars::Vector{Variable}
    tensors::Vector{BoolTensor}
    v2t::Vector{Vector{Int}}
    t2v::Vector{Vector{EdgeRef}}
    axis_of_t::Dict{Tuple{Int,Int},Int}
    # 预计算的 tensor masks: 从 tensor.tensor 映射到 TensorMasks
    # 这样可以复用相同张量类型的 masks，避免重复计算
    precomputed_masks::Dict{Vector{Tropical{Float64}}, TensorMasks}
    # 每个 tensor 实例到其预计算 masks 的映射 (索引优化)
    tensor_to_masks::Vector{TensorMasks}
end

function Base.show(io::IO, tn::TNStatic)
    print(io, "TNStatic(vars=$(length(tn.vars)), tensors=$(length(tn.tensors)))")
end

function Base.show(io::IO, ::MIME"text/plain", tn::TNStatic)
    println(io, "TNStatic:")
    println(io, "  variables: $(length(tn.vars))")
    println(io, "  tensors: $(length(tn.tensors))")
    println(io, "  variable-tensor incidence: $(length(tn.v2t))")
    println(io, "  tensor-variable incidence: $(length(tn.t2v))")
    println(io, "  axis mappings: $(length(tn.axis_of_t))")
end

function setup_problem(var_num::Int,
                       tensors_to_vars::Vector{Vector{Int}},
                       tensor_data::Vector{Vector{Tropical{Float64}}})
    F = length(tensors_to_vars)
    tensors = Vector{BoolTensor}(undef, F)
    vars_to_tensors = [Int[] for _ in 1:var_num]
    tensors_to_edges = [EdgeRef[] for _ in 1:F]
    for i in 1:F
        var_axes = tensors_to_vars[i]
        @assert length(tensor_data[i]) == 1 << length(var_axes)
        tensors[i] = BoolTensor(i, var_axes, tensor_data[i])
        for (j, v) in enumerate(var_axes)
            push!(vars_to_tensors[v], i)
            push!(tensors_to_edges[i], EdgeRef(v, j))
        end
    end

    axis_of_t = Dict{Tuple{Int,Int},Int}()
    for (fid, tensor) in enumerate(tensors)
        for (axis, vid) in enumerate(tensor.var_axes)
            axis_of_t[(fid, vid)] = axis
        end
    end

    vars = Vector{Variable}(undef, var_num)
    for i in 1:var_num
        vars[i] = Variable(i, 2, length(vars_to_tensors[i]))
    end

    # 预计算所有唯一张量的 masks
    # 策略：使用哈希值快速查找相同的张量，避免重复计算
    tensor_to_masks = Vector{TensorMasks}(undef, F)

    # 使用哈希值作为键的字典来快速查找
    hash_to_masks = Dict{UInt, TensorMasks}()
    hash_to_tensor = Dict{UInt, Vector{Tropical{Float64}}}()

    for (i, tensor) in enumerate(tensors)
        # 计算张量内容的哈希值
        tensor_hash = hash(tensor.tensor)

        if haskey(hash_to_masks, tensor_hash)
            # 哈希冲突检查：确保内容真的相同
            if hash_to_tensor[tensor_hash] == tensor.tensor
                # 复用已计算的 masks
                tensor_to_masks[i] = hash_to_masks[tensor_hash]
            else
                # 哈希冲突，重新计算
                masks = build_tensor_masks(tensor)
                tensor_to_masks[i] = masks
                # 注意：这里我们不更新字典，因为哈希冲突
            end
        else
            # 第一次遇到这个哈希值，计算 masks
            masks = build_tensor_masks(tensor)
            hash_to_masks[tensor_hash] = masks
            hash_to_tensor[tensor_hash] = tensor.tensor
            tensor_to_masks[i] = masks
        end
    end

    # 构建 precomputed_masks 字典用于统计（从唯一的张量构建）
    precomputed_masks = Dict{Vector{Tropical{Float64}}, TensorMasks}(
        hash_to_tensor[h] => hash_to_masks[h] for h in keys(hash_to_masks)
    )

    return TNStatic(vars, tensors, vars_to_tensors, tensors_to_edges, axis_of_t,
                    precomputed_masks, tensor_to_masks)
end

function setup_from_tensor_network(tn)::TNStatic
    t2v = getixsv(tn.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), tn)
    vec_tensors = [vec(t) for t in tensors]
    new_tensors = [replace(t, Tropical(1.0) => zero(Tropical{Float64})) for t in vec_tensors]
    return setup_problem(length(tn.problem.symbols), t2v, new_tensors)
end

