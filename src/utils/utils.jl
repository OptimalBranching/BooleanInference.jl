import ProblemReductions: BooleanExpr, simple_form, extract_symbols!

const _TRUE_SYMBOL = Symbol("true")
const _FALSE_SYMBOL = Symbol("false")

@inline function get_unfixed_vars(problem::TNProblem)::Vector{Int}
    unfixed_vars = Int[]
    @inbounds for (i, dm) in enumerate(problem.doms)
        if !is_fixed(dm)
            push!(unfixed_vars, i)
        end
    end
    return unfixed_vars
end

function get_unfixed_vars(problem::TNProblem, tensor_ids::Vector{Int})
    unfixed_vars = Vector{Vector{Int}}(undef, length(tensor_ids))
    @inbounds for (i, tensor_id) in enumerate(tensor_ids)
        unfixed = Int[]
        vars = problem.static.tensors[tensor_id].var_axes
        @inbounds for var_id in vars
            if !is_fixed(problem.doms[var_id])
                push!(unfixed, var_id)
            end
        end
        unfixed_vars[i] = unfixed
    end
    return unfixed_vars
end

# Convenience: compute number of unfixed variables quickly.
@inline function count_unfixed(doms::Vector{DomainMask})::Int
    c::Int = 0
    @inbounds for dm in doms
        if !is_fixed(dm)
            c += 1
        end
    end
    return c
end

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
