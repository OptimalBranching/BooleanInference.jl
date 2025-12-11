# Result type for branch-and-reduce solving
struct Result
    found::Bool
    solution::Vector{DomainMask}
    stats::BranchingStats
end

function Base.show(io::IO, r::Result)
    if r.found
        print(io, "Result(found=true, solution=available)")
    else
        print(io, "Result(found=false)")
    end
end

struct Assignment
    var_id::Int
    value::DomainMask
    reason_tensor::Int
    level::Int
end

function Base.show(io::IO, a::Assignment)
    if a.reason_tensor == 0
        print(io, "x$(a.var_id)@$(a.level) ← $(a.value) (direct decision)")
    else
        print(io, "x$(a.var_id)@$(a.level) ← $(a.value) (reason: tensor $(a.reason_tensor))")
    end
end

struct SolverBuffer
    touched_tensors::Vector{Int}  # Tensors that need propagation
    in_queue::BitVector           # Track which tensors are queued for processing
    scratch_doms::Vector{DomainMask}  # Temporary domain storage for propagation
    branching_cache::Dict{Clause{UInt64}, Float64}  # Cache measure values for branching configurations
    activity_scores::Vector{Float64}
    connection_scores::Vector{Float64}

    trail::Vector{Assignment}
    trail_lim::Vector{Int}

    # === CDCL 加速查找表 (Indexed by var_id) ===
    # 避免遍历 trail，实现 O(1) 查找
    var_to_level::Vector{Int}      # 变量的决策层级 (未赋值为 -1)
    var_to_reason::Vector{Int}     # 导致赋值的 Tensor ID (0 表示 Decision)
    
    # === 冲突分析复用 ===
    seen::BitVector                # 标记变量是否已处理
    seen_list::Vector{Int}         # 记录本次分析标记了哪些变量 (用于快速清空)
    
    # === 学习子句存储 ===
    learned_clauses::Vector{Vector{Tuple{Int, DomainMask}}}  # 存储所有学习到的子句
    learned_clauses_signatures::Set{UInt64}  # 用于去重检查（子句的哈希签名）
    current_clause::Vector{Tuple{Int, DomainMask}}           # 当前正在构建的子句（复用缓冲）
end

function SolverBuffer(cn::ConstraintNetwork)
    n_tensors = length(cn.tensors)
    n_vars = length(cn.vars)
    SolverBuffer(
        sizehint!(Int[], n_tensors),
        falses(n_tensors),
        Vector{DomainMask}(undef, n_vars),
        Dict{Clause{UInt64}, Float64}(),
        zeros(Float64, n_vars),
        zeros(Float64, n_vars),
        sizehint!(Assignment[], n_vars), Int[],
        fill(-1, n_vars),  # var_to_level: -1 indicates unassigned
        zeros(Int, n_vars),  # var_to_reason: 0 indicates decision or unassigned
        falses(n_vars),
        Int[],
        Vector{Vector{Tuple{Int, DomainMask}}}(),
        Set{UInt64}(),
        Vector{Tuple{Int, DomainMask}}()
    )
end

struct TNProblem <: AbstractProblem
    static::ConstraintNetwork
    doms::Vector{DomainMask}
    stats::BranchingStats
    buffer::SolverBuffer

    # Internal constructor: final constructor that creates the instance
    function TNProblem(static::ConstraintNetwork, doms::Vector{DomainMask}, stats::BranchingStats, buffer::SolverBuffer)
        new(static, doms, stats, buffer)
    end
end

# Constructor 1: Initialize from ConstraintNetwork (auto-propagate)
function TNProblem(static::ConstraintNetwork)
    buffer = SolverBuffer(static)
    doms = propagate(static, init_doms(static), collect(1:length(static.tensors)), buffer)
    has_contradiction(doms) && error("Domain has contradiction")
    return TNProblem(static, doms, BranchingStats(), buffer)
end

# Constructor 2: Create with explicit domains (creates new buffer)
function TNProblem(static::ConstraintNetwork, doms::Vector{DomainMask}, stats::BranchingStats=BranchingStats())
    buffer = SolverBuffer(static)
    return TNProblem(static, doms, stats, buffer)
end

function Base.show(io::IO, problem::TNProblem)
    print(io, "TNProblem(unfixed=$(count_unfixed(problem))/$(length(problem.static.vars)))")
end

get_var_value(problem::TNProblem, var_id::Int) = get_var_value(problem.doms, var_id)
get_var_value(problem::TNProblem, var_ids::Vector{Int}) = Bool[get_var_value(problem.doms, var_id) for var_id in var_ids]

count_unfixed(problem::TNProblem) = count_unfixed(problem.doms)
is_solved(problem::TNProblem) = count_unfixed(problem) == 0

get_branching_stats(problem::TNProblem) = copy(problem.stats)

function reset_problem!(problem::TNProblem)
    reset!(problem.stats)
    empty!(problem.buffer.branching_cache)
    clear_trail!(problem.buffer)
end

reset_propagated_cache!(problem::TNProblem) = empty!(problem.buffer.branching_cache)