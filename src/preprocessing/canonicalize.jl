# ============================================================================
# Static, width-aware constraint-network canonicalizer (bounded-width VE).
#
# Generalizes `precontract_degree2!` (src/core/static.jl) from "eliminate any
# degree-2 variable" to "eliminate any variable whose elimination stays under a
# space-complexity budget B, in weighted-min-fill order". Degree-2-greedy is not
# width-aware and P6 showed it *raises* treewidth; min-fill ordering with a per-
# step width cap keeps it bounded.
# ============================================================================

"""
    bounded_ve_canonicalize(cn::ConstraintNetwork; budget_B::Real,
                            protected=Int[],
                            order::Symbol=:weighted_min_fill) -> ConstraintNetwork

Reshape `cn` by bucket-eliminating variables once, statically, before any search.
Eliminating a variable `v` joins all tensors incident to `v` and projects `v` out
(boolean ∃/∧ semantics, exactly as `contract_two_tensors`). A variable is eliminated
only if the join's space complexity (`sc`, log2 of the largest intermediate under
`GreedyMethod`) is `<= budget_B`; eligible variables are removed in weighted-min-fill
order (fewest new neighbor edges first, `sc` as tiebreaker). `budget_B` is the single
fine↔coarse knob.

`protected` lists variable ids (in `cn`'s own id space) that must NEVER be eliminated —
the read-out variables (e.g. factor bits). They survive into the result, so their values can
be read directly off the solved reduced network via `result.orig_to_new[orig_id]` — no VE
back-substitution needed. Eliminated (non-protected) variables' values are *not* recoverable,
which is fine when only the protected variables are read.

Produced tensors are additionally hard-capped at 32 variables, the limit of the `TensorData`
representation (UInt32 config indices / 32-bit support masks), regardless of `budget_B`.

Returns a new compressed `ConstraintNetwork` whose remaining variables form the branch set
(protected variables ⊆ branch set).
"""
function bounded_ve_canonicalize(cn::ConstraintNetwork; budget_B::Real,
                                 protected=Int[],
                                 order::Symbol=:weighted_min_fill)
    order == :weighted_min_fill || throw(ArgumentError("unsupported order $order"))
    protected_set = Set{Int}(protected)
    B = Float64(budget_B)
    nv = length(cn.vars)
    # TensorData stores configs as UInt32 (support indices + 32-bit support_or/and masks),
    # so a produced tensor can hold at most 32 variables. Hard structural cap, regardless of B.
    # In practice budget_B binds first (a dense 2^arity tensor is infeasible well before 32).
    MAX_ARITY = 32

    # Mutable working copies in cn-variable-id space. Deep-copy var_axes so we never
    # mutate the input network (compress_variables! rewrites var_axes in place).
    tensors = [BoolTensor(copy(t.var_axes), t.tensor_data_idx) for t in cn.tensors]
    vars_to_tensors = [copy(lst) for lst in cn.v2t]
    unique_data = copy(cn.unique_tensors)
    data_to_idx = Dict{BitVector,Int}()
    for (i, td) in enumerate(unique_data)
        get!(data_to_idx, td.dense_tensor, i)
    end
    active = trues(length(tensors))

    active_incident(v) = filter(t -> active[t], vars_to_tensors[v])

    # Variables of the join of v's incident tensors, minus v (the produced tensor axes).
    function out_vars(tids, v)
        out = Int[]
        @inbounds for t in tids, x in tensors[t].var_axes
            x != v && !(x in out) && push!(out, x)
        end
        return out
    end

    # Space complexity of eliminating v under the current state (no array execution).
    function elim_sc(tids, out)
        code = EinCode([copy(tensors[t].var_axes) for t in tids], out)
        sd = uniformsize(code, 2)
        return contraction_complexity(optimize_code(code, sd, GreedyMethod()), sd).sc
    end

    # Weighted-min-fill: number of neighbor pairs not already sharing an active tensor.
    function fill_count(out)
        f = 0
        @inbounds for i in 1:length(out)-1, j in i+1:length(out)
            a, b = out[i], out[j]
            share = false
            for t in vars_to_tensors[a]
                if active[t] && b in tensors[t].var_axes
                    share = true; break
                end
            end
            share || (f += 1)
        end
        return f
    end

    # (eligible, fill, sc) for variable v in the current state.
    function score(v)
        v in protected_set && return (false, 0, Inf)   # read-out var: never eliminate
        tids = active_incident(v)
        isempty(tids) && return (false, 0, Inf)   # isolated: nothing to eliminate
        out = out_vars(tids, v)
        length(out) > MAX_ARITY && return (false, 0, Inf)   # too wide for TensorData
        sc = elim_sc(tids, out)
        return (sc <= B, fill_count(out), sc)
    end

    pq = PriorityQueue{Int,Tuple{Int,Float64}}()
    for v in 1:nv
        elig, f, sc = score(v)
        elig && (pq[v] = (f, sc))
    end

    while !isempty(pq)
        v = dequeue!(pq)
        tids = active_incident(v)
        isempty(tids) && continue
        out = out_vars(tids, v)
        length(out) > MAX_ARITY && continue                       # too wide for TensorData
        code = EinCode([copy(tensors[t].var_axes) for t in tids], out)
        sd = uniformsize(code, 2)
        optcode = optimize_code(code, sd, GreedyMethod())
        contraction_complexity(optcode, sd).sc <= B || continue   # stale: no longer eligible

        # Execute the bucket contraction -> dense BitVector over `out`.
        arrs = [reshape(Int.(unique_data[tensors[t].tensor_data_idx].dense_tensor),
                        ntuple(_ -> 2, length(tensors[t].var_axes))) for t in tids]
        res = optcode(arrs...)
        gt = res .> 0
        new_data = gt isa AbstractArray ? BitVector(vec(gt)) : BitVector([gt])

        # Deduplicate produced tensor data (flyweight, as in setup_problem).
        idx = get(data_to_idx, new_data, 0)
        if idx == 0
            push!(unique_data, TensorData(new_data))
            idx = length(unique_data)
            data_to_idx[new_data] = idx
        end

        # Rewrite incidence: reuse the first slot for the merged tensor, drop the rest.
        keep = tids[1]
        for t in tids
            for x in tensors[t].var_axes
                filter!(tt -> tt != t, vars_to_tensors[x])
            end
        end
        for t in tids[2:end]
            active[t] = false
        end
        tensors[keep] = BoolTensor(copy(out), idx)
        for x in out
            push!(vars_to_tensors[x], keep)
        end
        # v now has no active incident tensor -> eliminated.

        # Re-score only the affected neighbors (the merged tensor's variables).
        for u in out
            elig, f, scu = score(u)
            if elig
                pq[u] = (f, scu)
            elseif haskey(pq, u)
                delete!(pq, u)
            end
        end
    end

    # Compact active tensors, rebuild incidence, then compress variable ids.
    active_idx = findall(active)
    new_tensors = tensors[active_idx]
    new_vars_to_tensors = [Int[] for _ in 1:nv]
    for (newt, _) in enumerate(active_idx)
        for x in new_tensors[newt].var_axes
            push!(new_vars_to_tensors[x], newt)
        end
    end

    new_tensors, compressed_v2t, compress_o2n =
        compress_variables!(new_tensors, new_vars_to_tensors)
    vars = [Variable(length(compressed_v2t[i])) for i in 1:length(compressed_v2t)]

    # Compose with cn's own orig->compressed map so the result indexes original var ids.
    orig_to_new = zeros(Int, length(cn.orig_to_new))
    for orig in 1:length(cn.orig_to_new)
        cnid = cn.orig_to_new[orig]
        orig_to_new[orig] = cnid == 0 ? 0 : compress_o2n[cnid]
    end

    return ConstraintNetwork(vars, unique_data, new_tensors, compressed_v2t, orig_to_new)
end
