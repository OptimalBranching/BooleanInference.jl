mutable struct PropagationBuffers
    feasible::BitVector
    temp::BitVector
    max_configs::Int
end

function PropagationBuffers(static::TNStatic)
    max_nvars = maximum(length(t.var_axes) for t in static.tensors; init=0)
    max_configs = max_nvars > 0 ? (1 << max_nvars) : 1
    return PropagationBuffers(falses(max_configs), falses(max_configs), max_configs)
end

mutable struct DynamicWorkspace
    # Cache the full solution from the last branch for quick restoration
    cached_doms::Vector{DomainMask}
    has_cached_solution::Bool
    # Branching statistics
    branch_stats::BranchingStats
    # O(1) membership test to avoid O(n) scans
    changed_vars_flags::BitVector
    changed_vars_indices::Vector{Int}
    # Temporary BitVector cache for propagation to avoid reallocations
    prop_buffers::Union{Nothing, PropagationBuffers}
    # Cache of branch applications to avoid recomputing apply_branch
    # Inner dict maps (variables_id, clause_key) -> BranchCacheEntry
    # Note: clause_key type varies (Tuple{INT,INT}), so we can't fully type the key
    branch_cache::Dict{UInt, Dict}
    trail::Trail
    # Temporary buffer for evaluate_branch/commit_branch to avoid allocating new_doms on each call
    temp_doms::Vector{DomainMask}
end

DynamicWorkspace(var_num::Int, verbose::Bool = false) = DynamicWorkspace(
    Vector{DomainMask}(undef, var_num),
    false,
    BranchingStats(verbose),
    falses(var_num),
    Int[],
    nothing,
    Dict{UInt, Dict}(),
    Trail(var_num),
    Vector{DomainMask}(undef, var_num)
)

@inline function clear_branch_cache!(ws::DynamicWorkspace, doms_id::UInt)
    inner = pop!(ws.branch_cache, doms_id, nothing)
    if !isnothing(inner)
        empty!(inner)
    end
    return nothing
end
