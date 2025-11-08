struct Assignment
    var::Int
    value::Bool
    level::Int
    reason::Union{Int, Nothing}
    Assignment(var::Int, value::Bool, level::Int, reason::Union{Int, Nothing}=nothing) = new(var, value, level, reason)
end

function Base.show(io::IO, a::Assignment)
    value_str = a.value ? "T" : "F"
    reason_str = isnothing(a.reason) ? "" : " (reason: $(a.reason))"
    print(io, "x$(a.var)=$(value_str)$(reason_str)")
end

mutable struct Trail
    stack::Vector{Assignment}
    level_start::Vector{Int}
end

function Trail(var_num::Int)
    # worst case: all variables assigned
    stack = Vector{Assignment}()
    sizehint!(stack, var_num)
    
    level_start = Int[]
    sizehint!(level_start, max(8, var_num ÷ 10))    
    return Trail(stack, level_start)
end

function assign_var!(trail::Trail, var::Int, value::Bool, level::Int, reason::Union{Int, Nothing}=nothing)
    push!(trail.stack, Assignment(var, value, level, reason))
    # Create a new level if this is the first assignment at this level
    # level_start[i] stores the stack position where level i-1 starts (1-indexed)
    current_num_levels = length(trail.level_start)
    if current_num_levels < level + 1
        # Need to create level start for this new decision level
        push!(trail.level_start, length(trail.stack))
    end
end

function backtrack!(trail::Trail, level::Int)
    if isempty(trail.level_start) || level > last(trail.level_start)
        error("Backtrack to level $level is not possible")
    end
    for i in trail.level_start[level]:(trail.level_start[level+1]-1)
        pop!(trail.stack)
    end
    pop!(trail.level_start, level)
end

# Backtrack to a specific trail state (used in branch_and_reduce)
function backtrack_trail!(trail::Trail, target_level_count::Int, target_stack_size::Int)
    # Pop all level starts added after target
    while length(trail.level_start) > target_level_count
        pop!(trail.level_start)
    end
    # Pop all assignments added after target
    while length(trail.stack) > target_stack_size
        pop!(trail.stack)
    end
end

function Base.show(io::IO, trail::Trail)
    n_assignments = length(trail.stack)
    n_levels = length(trail.level_start)
    
    if n_assignments == 0
        print(io, "Trail(empty)")
        return
    end
    
    println(io, "Trail with $(n_assignments) assignment$(n_assignments == 1 ? "" : "s") across $(n_levels) decision level$(n_levels == 1 ? "" : "s"):")

    # Show detailed breakdown by level
    # Note: level_idx is 1-indexed for array access, but we display the actual decision level (0-indexed)
    for level_idx in 1:n_levels
        start_idx = trail.level_start[level_idx]
        end_idx = level_idx < n_levels ? trail.level_start[level_idx + 1] - 1 : n_assignments

        assignments_in_level = trail.stack[start_idx:end_idx]
        n_in_level = length(assignments_in_level)

        # Get the actual decision level from the first assignment in this level
        actual_level = isempty(assignments_in_level) ? level_idx - 1 : assignments_in_level[1].level

        print(io, "  Level $(actual_level) ($(n_in_level) assignment$(n_in_level == 1 ? "" : "s")): ")
        
        if n_in_level <= 100
            assignment_strs = [string(a) for a in assignments_in_level]
            print(io, join(assignment_strs, ", "))
        else
            # Show first few and last few if too many
            first_few = [string(a) for a in assignments_in_level[1:3]]
            last_few = [string(a) for a in assignments_in_level[(end-2):end]]
            print(io, join(first_few, ", "), ", ..., ", join(last_few, ", "))
        end
        println(io)
    end
end


# 获取导致某个赋值的前驱变量（在同一 tensor 中的其他已赋值变量）
function get_reason_vars(trail::Trail, assignment::Assignment, static::TNStatic)
    isnothing(assignment.reason) && return Int[]  # 决策变量
    
    tensor = static.tensors[assignment.reason]
    reason_vars = Int[]
    
    # 找到 tensor 中所有在 assignment 之前被赋值的变量
    for var_id in tensor.var_axes
        var_id == assignment.var && continue
        # 在 trail 中查找这个变量的赋值
        # （可以优化：维护一个 var_id -> trail_index 的映射）
        push!(reason_vars, var_id)
    end
    
    return reason_vars
end