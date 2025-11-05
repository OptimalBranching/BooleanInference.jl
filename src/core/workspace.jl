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
    # 缓存上一次分支的完整解（用于快速恢复）
    cached_doms::Vector{DomainMask}
    has_cached_solution::Bool
    # 分支统计信息
    branch_stats::BranchingStats
    var_values::PriorityQueue{Int, Float64}
    # 快速 O(1) 成员测试（避免 O(n) 搜索）
    changed_vars_flags::BitVector
    changed_vars_indices::Vector{Int}
    # 缓存传播时的临时 BitVector（避免重复分配）
    prop_buffers::Union{Nothing, PropagationBuffers}
    # 分支应用缓存：避免重复 compute apply_branch
    branch_cache::Dict{UInt, Dict{Tuple{UInt, Any}, Any}}
end

DynamicWorkspace(var_num::Int, verbose::Bool = false) = DynamicWorkspace(
    Vector{DomainMask}(undef, var_num),
    false,
    BranchingStats(verbose),
    PriorityQueue{Int, Float64}(),
    falses(var_num),
    Int[],
    nothing,
    Dict{UInt, Dict{Tuple{UInt, Any}, Any}}()
)

@inline function clear_branch_cache!(ws::DynamicWorkspace, doms_id::UInt)
    inner = pop!(ws.branch_cache, doms_id, nothing)
    if !isnothing(inner)
        empty!(inner)
    end
    return nothing
end
