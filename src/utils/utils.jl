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
  
function get_active_tensors(static::BipartiteGraph, doms::Vector{DomainMask})
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
