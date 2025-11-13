struct BipartiteGraph
    vars::Vector{Variable}
    tensors::Vector{BoolTensor}
    v2t::Vector{Vector{Int}}
    tensor_to_masks::Vector{TensorMasks}
    tensor_depths::Vector{Int}
    tensor_fanin::Vector{Vector{Int}}
    tensor_fanout::Vector{Vector{Int}}
end

function Base.show(io::IO, tn::BipartiteGraph)
    print(io, "BipartiteGraph(vars=$(length(tn.vars)), tensors=$(length(tn.tensors)))")
end

function Base.show(io::IO, ::MIME"text/plain", tn::BipartiteGraph)
    println(io, "BipartiteGraph:")
    println(io, "  variables: $(length(tn.vars))")
    println(io, "  tensors: $(length(tn.tensors))")
    println(io, "  variable-tensor incidence: $(length(tn.v2t))")
end

function setup_problem(var_num::Int,
                       tensors_to_vars::Vector{Vector{Int}},
                       tensor_data::Vector{Vector{Tropical{Float64}}};
                       tensor_depths::Vector{Int}=Int[],
                       tensor_fanin::Vector{Vector{Int}}=Vector{Int}[],
                       tensor_fanout::Vector{Vector{Int}}=Vector{Int}[])
    F = length(tensors_to_vars)
    tensors = Vector{BoolTensor}(undef, F)
    vars_to_tensors = [Int[] for _ in 1:var_num]
    for i in 1:F
        var_axes = tensors_to_vars[i]
        @assert length(tensor_data[i]) == 1 << length(var_axes)
        tensors[i] = BoolTensor(var_axes, tensor_data[i])
        for v in var_axes
            push!(vars_to_tensors[v], i)
        end
    end

    vars = Vector{Variable}(undef, var_num)
    for i in 1:var_num
        vars[i] = Variable(length(vars_to_tensors[i]))
    end

    # Precompute masks for every unique tensor
    # Strategy: use hash values to quickly find identical tensors and avoid recomputation
    tensor_to_masks = Vector{TensorMasks}(undef, F)

    # Dictionary keyed by hash for fast lookup during construction
    hash_to_masks = Dict{UInt, TensorMasks}()

    for (i, tensor) in enumerate(tensors)
        # Compute the hash of the tensor contents
        tensor_hash = hash(tensor.tensor)

        if haskey(hash_to_masks, tensor_hash)
            # Reuse the previously computed masks
            tensor_to_masks[i] = hash_to_masks[tensor_hash]
        else
            # First time we see this hash, compute the masks
            masks = build_tensor_masks(tensor)
            hash_to_masks[tensor_hash] = masks
            tensor_to_masks[i] = masks
        end
    end

    if isempty(tensor_depths)
        tensor_depths = zeros(Int, F)
    end
    if isempty(tensor_fanin)
        tensor_fanin = [Int[] for _ in 1:F]
    end
    if isempty(tensor_fanout)
        tensor_fanout = [Int[] for _ in 1:F]
    end

    return BipartiteGraph(vars, tensors, vars_to_tensors, tensor_to_masks, tensor_depths, tensor_fanin, tensor_fanout)
end

function setup_from_tensor_network(tn;
                                   tensor_depths::Vector{Int}=Int[],
                                   tensor_fanin::Vector{Vector{Int}}=Vector{Int}[],
                                   tensor_fanout::Vector{Vector{Int}}=Vector{Int}[])::BipartiteGraph
    t2v = getixsv(tn.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), tn)
    # Merge vec + replace to avoid intermediate allocation
    new_tensors = [replace(vec(t), Tropical(1.0) => zero(Tropical{Float64})) for t in tensors]
    return setup_problem(length(tn.problem.symbols), t2v, new_tensors;
                        tensor_depths=tensor_depths,
                        tensor_fanin=tensor_fanin,
                        tensor_fanout=tensor_fanout)
end
