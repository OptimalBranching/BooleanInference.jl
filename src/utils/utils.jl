@inline function get_unfixed_vars(problem::TNProblem)::Vector{Int}
    unfixed_vars = Int[]
    @inbounds for (i, dm) in enumerate(problem.doms)
        !is_fixed(dm) && push!(unfixed_vars, i)
    end
    return unfixed_vars
end

function get_unfixed_vars(problem::TNProblem, tensor_ids::Vector{Int})
    unfixed_vars = Vector{Vector{Int}}(undef, length(tensor_ids))
    @inbounds for (i, tensor_id) in enumerate(tensor_ids)
        unfixed = Int[]
        vars = problem.static.tensors[tensor_id].var_axes
        @inbounds for var_id in vars
            !is_fixed(problem.doms[var_id]) && push!(unfixed, var_id)
        end
        unfixed_vars[i] = unfixed
    end
    return unfixed_vars
end

count_unfixed(doms::Vector{DomainMask}) = count(dom -> !is_fixed(dom), doms)

bits_to_int(v::Vector{Bool}) = sum(b << (i - 1) for (i, b) in enumerate(v))
  
function get_active_tensors(static::ConstraintNetwork, doms::Vector{DomainMask})
    active = Int[]
    sizehint!(active, length(static.tensors))
    @inbounds for (tid, tensor) in enumerate(static.tensors)
        # Check if any variable in this tensor is unfixed
        has_unfixed = false
        for var_id in tensor.var_axes
            is_fixed(doms[var_id]) && continue
            has_unfixed = true
            break
        end
        has_unfixed && push!(active, tid)
    end
    return active
end

# Check if a variable is masked (fixed) in the clause
ismasked(clause::Clause, var_idx::Int) = (clause.mask >> (var_idx - 1)) & 1 == 1

# Get the value for a variable from the clause
getbit(clause::Clause, var_idx::Int) = (clause.val >> (var_idx - 1)) & 1 == 1

function is_legal(checklist::Vector{DomainMask})
    mask = UInt64(0)
    value = UInt64(0)
    @inbounds for (var_idx, v) in enumerate(checklist)
        v == DM_BOTH && continue
        bit = UInt64(1) << (var_idx-1)
        mask |= bit
        if v == DM_1
            value |= bit
        end
    end
    return mask, value
end

@inline function mask_value(doms::Vector{DomainMask}, vars::Vector{Int}, ::Type{T}) where {T<:Unsigned}
    mask = zero(T)
    value = zero(T)
    @inbounds for (i, var_id) in enumerate(vars)
        dm = doms[var_id]
        if dm == DM_1
            bit = T(1) << (i - 1)
            mask |= bit
            value |= bit
        elseif dm == DM_0
            mask |= (T(1) << (i - 1))
        end
    end
    return mask, value
end

packint(bits::NTuple{N, Int}) where {N} = reduce(|, (UInt64(b) << (i - 1) for (i, b) in enumerate(bits)); init = UInt64(0))
packint(i::Int) = packint((i - 1,))
packint(ci::CartesianIndex{N}) where {N} = packint(ntuple(j -> ci.I[j] - 1, N))

function is_two_sat(doms::Vector{DomainMask}, static::ConstraintNetwork)
    @inbounds for tensor in static.tensors
        vars = tensor.var_axes
        unfixed_count = 0
        @inbounds for var_id in vars
            !is_fixed(doms[var_id]) && (unfixed_count += 1)
            unfixed_count > 2 && return false
        end
    end
    return true
end

function primal_graph(static::ConstraintNetwork, doms::Vector{DomainMask})
    
    g = SimpleGraph(length(doms))

    active_tensors = get_active_tensors(static, doms)
    for tensor_id in active_tensors
        vars = static.tensors[tensor_id].var_axes
        unfixed_vars_in_tensor = filter(var -> !is_fixed(doms[var]), vars)
        for vertex_pair in combinations(unfixed_vars_in_tensor, 2)
            add_edge!(g, vertex_pair[1], vertex_pair[2])
        end
    end
    return g
end