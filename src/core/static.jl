struct BipartiteGraph
    vars::Vector{Variable}
    tensors::Vector{BoolTensor}
    v2t::Vector{Vector{Int}}
    t2v::Vector{Vector{EdgeRef}}
    axis_of_t::Dict{Tuple{Int,Int},Int}
    # Precomputed tensor masks: maps tensor.tensor to TensorMasks
    # Reuse masks for identical tensor shapes to avoid recomputation
    precomputed_masks::Dict{Vector{Tropical{Float64}}, TensorMasks}
    # Map each tensor instance to its precomputed masks (indexing optimization)
    tensor_to_masks::Vector{TensorMasks}
end

function Base.show(io::IO, tn::BipartiteGraph)
    print(io, "BipartiteGraph(vars=$(length(tn.vars)), tensors=$(length(tn.tensors)))")
end

function Base.show(io::IO, ::MIME"text/plain", tn::BipartiteGraph)
    println(io, "BipartiteGraph:")
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

    # Precompute masks for every unique tensor
    # Strategy: use hash values to quickly find identical tensors and avoid recomputation
    tensor_to_masks = Vector{TensorMasks}(undef, F)

    # Dictionary keyed by hash for fast lookup
    hash_to_masks = Dict{UInt, TensorMasks}()
    hash_to_tensor = Dict{UInt, Vector{Tropical{Float64}}}()
    # Statistics: count how many tensors share each hash
    hash_to_count = Dict{UInt, Int}()

    for (i, tensor) in enumerate(tensors)
        # Compute the hash of the tensor contents
        tensor_hash = hash(tensor.tensor)

        if haskey(hash_to_masks, tensor_hash)
            # Hash collision check: ensure the contents truly match
            if hash_to_tensor[tensor_hash] == tensor.tensor
                # Reuse the previously computed masks
                tensor_to_masks[i] = hash_to_masks[tensor_hash]
                # Increment count for this hash
                hash_to_count[tensor_hash] = get(hash_to_count, tensor_hash, 0) + 1
            else
                error("Hash collision: $tensor_hash")
            end
        else
            # First time we see this hash, compute the masks
            masks = build_tensor_masks(tensor)
            hash_to_masks[tensor_hash] = masks
            hash_to_tensor[tensor_hash] = tensor.tensor
            tensor_to_masks[i] = masks
            # Initialize count for this hash
            hash_to_count[tensor_hash] = 1
        end
    end
    
    # Print statistics
    unique_tensors = length(hash_to_count)
    total_tensors = length(tensors)
    if unique_tensors < total_tensors
        @info "Tensor statistics: $unique_tensors unique tensor types (out of $total_tensors total)"
        # Show distribution if there are duplicates
        for (hash, count) in hash_to_count
            @info "Tensor $(hash_to_tensor[hash]) has $count instances"
        end
    end

    # Build the precomputed_masks dictionary for statistics (from unique tensors)
    precomputed_masks = Dict{Vector{Tropical{Float64}}, TensorMasks}(
        hash_to_tensor[h] => hash_to_masks[h] for h in keys(hash_to_masks)
    )

    return BipartiteGraph(vars, tensors, vars_to_tensors, tensors_to_edges, axis_of_t, precomputed_masks, tensor_to_masks)
end

function setup_from_tensor_network(tn)::BipartiteGraph
    t2v = getixsv(tn.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), tn)
    vec_tensors = [vec(t) for t in tensors]
    new_tensors = [replace(t, Tropical(1.0) => zero(Tropical{Float64})) for t in vec_tensors]
    return setup_problem(length(tn.problem.symbols), t2v, new_tensors)
end
