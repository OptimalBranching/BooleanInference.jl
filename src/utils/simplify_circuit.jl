# Simplify a ProblemReductions.Circuit object, keeping `fix_vars` symbols untouched.
# Rules: 1. structural hashing (in iteration); 2. constant propagation;
#        3. backward propagation; 4. dead code elimination
#        5. double negation elimination ¬¬a = a; 6. complement laws a∧¬a=false, a∨¬a=true
function simplify_circuit(circuit::Circuit, fix_vars::Vector{Int}=Int[])
    original_symbols = ProblemReductions.symbols(circuit)
    fix_syms = Set{Symbol}()
    for idx in fix_vars
        (idx < 1 || idx > length(original_symbols)) && error("fix_vars index $idx out of range")
        push!(fix_syms, original_symbols[idx])
    end

    simplified = simple_form(circuit)
    before_gates = gate_count(circuit)

    # 核心数据结构
    replace_map = Dict{Symbol,Union{Bool,Symbol}}()  # sym -> canonical sym or Bool
    neg_of = Dict{Symbol,Symbol}()      # a -> b 表示 b = ¬a
    expr_hash = Dict{Tuple{Symbol,Tuple{Vararg{Symbol}}},Symbol}()  # 结构哈希

    max_iterations = 20
    for iteration in 1:max_iterations
        changed = false
        # 每轮重建结构哈希和否定映射
        empty!(expr_hash)
        empty!(neg_of)

        for ex in simplified.exprs
            for out in ex.outputs
                out in fix_syms && continue

                # 简化表达式，应用当前替换
                simp_expr = _simplify_expr_v2(ex.expr, replace_map, fix_syms, neg_of)

                if simp_expr.head == :var
                    sym = simp_expr.var
                    if sym == Symbol("true")
                        changed |= _set_replace!(replace_map, out, true, fix_syms)
                    elseif sym == Symbol("false")
                        changed |= _set_replace!(replace_map, out, false, fix_syms)
                    elseif sym != out
                        changed |= _set_replace!(replace_map, out, sym, fix_syms)
                    end
                else
                    # 结构哈希：相同表达式映射到同一符号
                    key = _expr_key(simp_expr)
                    if haskey(expr_hash, key)
                        canonical = expr_hash[key]
                        if canonical != out
                            changed |= _set_replace!(replace_map, out, canonical, fix_syms)
                        end
                    else
                        expr_hash[key] = out
                        # 记录否定关系用于互补律检测
                        if simp_expr.head == _NOT_HEAD
                            inner_sym = simp_expr.args[1].var
                            neg_of[inner_sym] = out
                        end
                    end
                end

                # 反向传播
                out_val = get(replace_map, out, nothing)
                if out_val isa Bool && simp_expr.head != :var
                    changed |= _backpropagate_v2(simp_expr, out_val, replace_map, fix_syms)
                end
            end
        end

        # 归一化替换映射
        replace_map = _normalize_replace_map(replace_map, fix_syms)
        !changed && break
    end

    # 最终重建电路
    new_exprs = Assignment[]
    final_hash = Dict{Tuple{Symbol,Tuple{Vararg{Symbol}}},Symbol}()
    final_neg = Dict{Symbol,Symbol}()

    for ex in simplified.exprs
        for out in ex.outputs
            simp_expr = _simplify_expr_v2(ex.expr, replace_map, fix_syms, final_neg)

            if simp_expr.head != :var
                key = _expr_key(simp_expr)
                if haskey(final_hash, key)
                    canonical = final_hash[key]
                    if out != canonical && !(out in fix_syms)
                        replace_map[out] = canonical
                        simp_expr = BooleanExpr(canonical)
                    end
                else
                    final_hash[key] = out
                    if simp_expr.head == _NOT_HEAD
                        final_neg[simp_expr.args[1].var] = out
                    end
                end
            end
            push!(new_exprs, Assignment([out], simp_expr))
        end
    end

    new_exprs = _dce_assignments(new_exprs, fix_syms)
    simplified_circuit = Circuit(new_exprs)
    after_gates = gate_count(simplified_circuit)
    @info "Simplify circuit" before_gates after_gates

    # 映射 fix_vars 到新索引
    simplified_symbols = ProblemReductions.symbols(simplified_circuit)
    fix_indices = Int[]
    for idx in fix_vars
        sym = original_symbols[idx]
        pos = findfirst(==(sym), simplified_symbols)
        pos === nothing && error("fixed var $sym not found in simplified circuit symbols")
        push!(fix_indices, pos)
    end

    return simplified_circuit, fix_indices
end

function simplify_circuit(circuit_sat::CircuitSAT, fix_vars::Vector{Int}=Int[])
    return simplify_circuit(circuit_sat.circuit, fix_vars)
end

function gate_count(circuit::Circuit)
    count(ex -> ex.expr.head != :var, circuit.exprs)
end

const _NOT_HEAD = Symbol("\u00ac")
const _AND_HEAD = Symbol("\u2227")
const _OR_HEAD = Symbol("\u2228")
const _XOR_HEAD = Symbol("\u22bb")

# 统一的替换设置，避免覆盖已有常量
function _set_replace!(replace_map::Dict{Symbol,Union{Bool,Symbol}}, sym::Symbol, val::Union{Bool,Symbol}, fix_syms::Set{Symbol})
    sym in fix_syms && return false
    sym == Symbol("true") || sym == Symbol("false") && return false
    existing = get(replace_map, sym, nothing)
    existing === val && return false
    existing isa Bool && return false  # 已经是常量，不覆盖
    replace_map[sym] = val
    return true
end

function _resolve_symbol(sym::Symbol, replace_map::Dict{Symbol,Union{Bool,Symbol}}, fix_syms::Set{Symbol})
    sym in fix_syms && return sym
    visited = Set{Symbol}()
    while haskey(replace_map, sym)
        sym in visited && return sym
        push!(visited, sym)
        val = replace_map[sym]
        if val isa Bool
            return val
        end
        val == sym && return sym
        sym = val
        sym in fix_syms && return sym
    end
    return sym
end

function _normalize_replace_map(replace_map::Dict{Symbol,Union{Bool,Symbol}}, fix_syms::Set{Symbol})
    normalized = Dict{Symbol,Union{Bool,Symbol}}()
    for (key, val) in replace_map
        key in fix_syms && continue
        if val isa Bool
            normalized[key] = val
            continue
        end
        resolved = _resolve_symbol(val, replace_map, fix_syms)
        if resolved isa Bool
            normalized[key] = resolved
        elseif resolved != key
            normalized[key] = resolved
        end
    end
    return normalized
end

function _backpropagate_from_fixed_output(
    expr::BooleanExpr,
    out_val::Bool,
    replace_map::Dict{Symbol,Union{Bool,Symbol}},
    fix_syms::Set{Symbol},
)
    head = expr.head
    args = expr.args
    changed = false

    if head == _NOT_HEAD
        arg_sym = args[1].var
        resolved = _resolve_symbol(arg_sym, replace_map, fix_syms)
        if resolved isa Bool
            return false
        end
        if !(resolved in fix_syms)
            desired = !out_val
            changed |= _try_set_var!(replace_map, resolved, desired, fix_syms)
        end
        return changed
    end

    if head == _AND_HEAD
        if out_val
            # AND = true => all inputs must be true
            for a in args
                resolved = _resolve_symbol(a.var, replace_map, fix_syms)
                if resolved isa Bool
                    continue
                end
                if !(resolved in fix_syms)
                    changed |= _try_set_var!(replace_map, resolved, true, fix_syms)
                end
            end
        else
            # AND = false => at least one input is false
            unknown_vars = Symbol[]
            for a in args
                resolved = _resolve_symbol(a.var, replace_map, fix_syms)
                if resolved isa Bool
                    if !resolved
                        return false  # already satisfied
                    end
                    continue
                end
                push!(unknown_vars, resolved)
            end
            non_fixed = filter(v -> !(v in fix_syms), unknown_vars)
            if length(non_fixed) == 1 && length(unknown_vars) == 1
                changed |= _try_set_var!(replace_map, non_fixed[1], false, fix_syms)
            end
        end
        return changed
    end

    if head == _OR_HEAD
        if !out_val
            # OR = false => all inputs must be false
            for a in args
                resolved = _resolve_symbol(a.var, replace_map, fix_syms)
                if resolved isa Bool
                    continue
                end
                if !(resolved in fix_syms)
                    changed |= _try_set_var!(replace_map, resolved, false, fix_syms)
                end
            end
        else
            # OR = true => at least one input is true
            unknown_vars = Symbol[]
            for a in args
                resolved = _resolve_symbol(a.var, replace_map, fix_syms)
                if resolved isa Bool
                    if resolved
                        return false  # already satisfied
                    end
                    continue
                end
                push!(unknown_vars, resolved)
            end
            non_fixed = filter(v -> !(v in fix_syms), unknown_vars)
            if length(non_fixed) == 1 && length(unknown_vars) == 1
                changed |= _try_set_var!(replace_map, non_fixed[1], true, fix_syms)
            end
        end
        return changed
    end

    if head == _XOR_HEAD
        parity = out_val
        unknown_vars = Symbol[]

        for a in args
            resolved = _resolve_symbol(a.var, replace_map, fix_syms)
            if resolved isa Bool
                if resolved
                    parity = !parity
                end
            else
                push!(unknown_vars, resolved)
            end
        end

        if isempty(unknown_vars)
            return false
        end

        if length(unknown_vars) == 1
            sym = unknown_vars[1]
            if !(sym in fix_syms)
                changed |= _try_set_var!(replace_map, sym, parity, fix_syms)
            end
        end
        # 多于一个未知变量时暂不处理

        return changed
    end

    return changed
end

function _try_set_var!(
    replace_map::Dict{Symbol,Union{Bool,Symbol}},
    sym::Symbol,
    val::Bool,
    fix_syms::Set{Symbol},
)
    sym in fix_syms && return false
    (sym == Symbol("true") || sym == Symbol("false")) && return false

    existing = get(replace_map, sym, nothing)
    if existing isa Bool
        return false
    end

    replace_map[sym] = val
    return true
end

# v2: 使用 _set_replace!，逻辑与原版相同
function _backpropagate_v2(
    expr::BooleanExpr,
    out_val::Bool,
    replace_map::Dict{Symbol,Union{Bool,Symbol}},
    fix_syms::Set{Symbol},
)
    head = expr.head
    args = expr.args
    changed = false

    if head == _NOT_HEAD
        arg_sym = args[1].var
        resolved = _resolve_symbol(arg_sym, replace_map, fix_syms)
        resolved isa Bool && return false
        resolved in fix_syms && return false
        return _set_replace!(replace_map, resolved, !out_val, fix_syms)
    end

    if head == _AND_HEAD
        if out_val
            # AND = true => all inputs must be true
            for a in args
                resolved = _resolve_symbol(a.var, replace_map, fix_syms)
                resolved isa Bool && continue
                resolved in fix_syms && continue
                changed |= _set_replace!(replace_map, resolved, true, fix_syms)
            end
        else
            # AND = false => 只有唯一一个非固定未知变量时可推断
            unknown_vars = Symbol[]
            for a in args
                resolved = _resolve_symbol(a.var, replace_map, fix_syms)
                if resolved isa Bool
                    !resolved && return false  # 已满足
                    continue
                end
                push!(unknown_vars, resolved)
            end
            non_fixed = filter(v -> !(v in fix_syms), unknown_vars)
            if length(non_fixed) == 1 && length(unknown_vars) == 1
                changed |= _set_replace!(replace_map, non_fixed[1], false, fix_syms)
            end
        end
        return changed
    end

    if head == _OR_HEAD
        if !out_val
            # OR = false => all inputs must be false
            for a in args
                resolved = _resolve_symbol(a.var, replace_map, fix_syms)
                resolved isa Bool && continue
                resolved in fix_syms && continue
                changed |= _set_replace!(replace_map, resolved, false, fix_syms)
            end
        else
            # OR = true => 只有唯一一个非固定未知变量时可推断
            unknown_vars = Symbol[]
            for a in args
                resolved = _resolve_symbol(a.var, replace_map, fix_syms)
                if resolved isa Bool
                    resolved && return false  # 已满足
                    continue
                end
                push!(unknown_vars, resolved)
            end
            non_fixed = filter(v -> !(v in fix_syms), unknown_vars)
            if length(non_fixed) == 1 && length(unknown_vars) == 1
                changed |= _set_replace!(replace_map, non_fixed[1], true, fix_syms)
            end
        end
        return changed
    end

    if head == _XOR_HEAD
        parity = out_val
        unknown_vars = Symbol[]
        for a in args
            resolved = _resolve_symbol(a.var, replace_map, fix_syms)
            if resolved isa Bool
                resolved && (parity = !parity)
            else
                push!(unknown_vars, resolved)
            end
        end
        isempty(unknown_vars) && return false
        if length(unknown_vars) == 1
            sym = unknown_vars[1]
            sym in fix_syms && return false
            changed |= _set_replace!(replace_map, sym, parity, fix_syms)
        end
        return changed
    end

    return changed
end

function _dce_assignments(exprs::Vector{Assignment}, fix_syms::Set{Symbol})
    live = Set{Symbol}(fix_syms)
    kept = Assignment[]

    for ex in Iterators.reverse(exprs)
        expr = ex.expr
        is_const = expr.head == :var && (expr.var == Symbol("true") || expr.var == Symbol("false"))
        keep = is_const
        for out in ex.outputs
            if out in live
                keep = true
                break
            end
        end
        keep || continue

        for out in ex.outputs
            push!(live, out)
        end
        _add_expr_symbols!(live, ex.expr)
        push!(kept, ex)
    end

    return reverse(kept)
end

function _add_expr_symbols!(live::Set{Symbol}, expr::BooleanExpr)
    if expr.head == :var
        (expr.var == Symbol("true") || expr.var == Symbol("false")) && return
        push!(live, expr.var)
        return
    end
    for arg in expr.args
        _add_expr_symbols!(live, arg)
    end
end

function _simplify_var(sym::Symbol, replace_map::Dict{Symbol,Union{Bool,Symbol}}, fix_syms::Set{Symbol})
    resolved = _resolve_symbol(sym, replace_map, fix_syms)
    if resolved isa Bool
        return BooleanExpr(resolved)
    end
    return BooleanExpr(resolved)
end

function _simplify_expr(expr::BooleanExpr, replace_map::Dict{Symbol,Union{Bool,Symbol}}, fix_syms::Set{Symbol})
    if expr.head == :var
        return _simplify_var(expr.var, replace_map, fix_syms)
    end

    if expr.head == _NOT_HEAD
        inner = _simplify_var(expr.args[1].var, replace_map, fix_syms)
        if inner.var == Symbol("true")
            return BooleanExpr(false)
        elseif inner.var == Symbol("false")
            return BooleanExpr(true)
        end
        return BooleanExpr(_NOT_HEAD, [inner])
    end

    syms = Symbol[]
    for arg in expr.args
        simp = _simplify_var(arg.var, replace_map, fix_syms)
        push!(syms, simp.var)
    end

    if expr.head == _AND_HEAD
        return _simplify_and(syms)
    elseif expr.head == _OR_HEAD
        return _simplify_or(syms)
    elseif expr.head == _XOR_HEAD
        return _simplify_xor(syms)
    end

    return expr
end

# v2: 支持双重否定消除和互补律检测
function _simplify_expr_v2(expr::BooleanExpr, replace_map::Dict{Symbol,Union{Bool,Symbol}}, fix_syms::Set{Symbol}, neg_of::Dict{Symbol,Symbol})
    if expr.head == :var
        return _simplify_var(expr.var, replace_map, fix_syms)
    end

    if expr.head == _NOT_HEAD
        inner = _simplify_var(expr.args[1].var, replace_map, fix_syms)
        inner_sym = inner.var
        if inner_sym == Symbol("true")
            return BooleanExpr(false)
        elseif inner_sym == Symbol("false")
            return BooleanExpr(true)
        end
        # 双重否定消除: ¬(¬a) = a
        # 如果 inner_sym 是某个 NOT 的输出，找到原始变量
        if haskey(neg_of, inner_sym)
            # inner_sym = ¬x，所以 ¬inner_sym = x，但这里需要反向查找
            # neg_of[x] = inner_sym 表示 inner_sym = ¬x
            # 我们需要: 如果存在 y 使得 neg_of[y] = inner_sym，则 ¬inner_sym = y
        end
        # 检查 inner_sym 是否本身就是 neg_of 的值（即是某个变量的否定）
        for (orig, neg) in neg_of
            if neg == inner_sym
                # inner_sym = ¬orig，所以 ¬inner_sym = orig
                return BooleanExpr(orig)
            end
        end
        return BooleanExpr(_NOT_HEAD, [inner])
    end

    syms = Symbol[]
    for arg in expr.args
        simp = _simplify_var(arg.var, replace_map, fix_syms)
        push!(syms, simp.var)
    end

    if expr.head == _AND_HEAD
        return _simplify_and_v2(syms, neg_of)
    elseif expr.head == _OR_HEAD
        return _simplify_or_v2(syms, neg_of)
    elseif expr.head == _XOR_HEAD
        return _simplify_xor(syms)
    end

    return expr
end

function _simplify_and(syms::Vector{Symbol})
    any(sym -> sym == Symbol("false"), syms) && return BooleanExpr(false)
    keep = [sym for sym in syms if sym != Symbol("true")]
    unique!(keep)
    sort!(keep, by=String)

    isempty(keep) && return BooleanExpr(true)
    length(keep) == 1 && return BooleanExpr(keep[1])
    return BooleanExpr(_AND_HEAD, BooleanExpr.(keep))
end

function _simplify_or(syms::Vector{Symbol})
    any(sym -> sym == Symbol("true"), syms) && return BooleanExpr(true)
    keep = [sym for sym in syms if sym != Symbol("false")]
    unique!(keep)
    sort!(keep, by=String)
    isempty(keep) && return BooleanExpr(false)
    length(keep) == 1 && return BooleanExpr(keep[1])
    return BooleanExpr(_OR_HEAD, BooleanExpr.(keep))
end

# v2: 支持互补律 a ∧ ¬a = false
function _simplify_and_v2(syms::Vector{Symbol}, neg_of::Dict{Symbol,Symbol})
    any(sym -> sym == Symbol("false"), syms) && return BooleanExpr(false)
    keep = [sym for sym in syms if sym != Symbol("true")]
    unique!(keep)

    # 互补律检测: 如果同时存在 a 和 ¬a，结果为 false
    keep_set = Set(keep)
    for s in keep
        if haskey(neg_of, s) && neg_of[s] in keep_set
            return BooleanExpr(false)
        end
    end

    sort!(keep, by=String)
    isempty(keep) && return BooleanExpr(true)
    length(keep) == 1 && return BooleanExpr(keep[1])
    return BooleanExpr(_AND_HEAD, BooleanExpr.(keep))
end

# v2: 支持互补律 a ∨ ¬a = true
function _simplify_or_v2(syms::Vector{Symbol}, neg_of::Dict{Symbol,Symbol})
    any(sym -> sym == Symbol("true"), syms) && return BooleanExpr(true)
    keep = [sym for sym in syms if sym != Symbol("false")]
    unique!(keep)

    # 互补律检测: 如果同时存在 a 和 ¬a，结果为 true
    keep_set = Set(keep)
    for s in keep
        if haskey(neg_of, s) && neg_of[s] in keep_set
            return BooleanExpr(true)
        end
    end

    sort!(keep, by=String)
    isempty(keep) && return BooleanExpr(false)
    length(keep) == 1 && return BooleanExpr(keep[1])
    return BooleanExpr(_OR_HEAD, BooleanExpr.(keep))
end

function _simplify_xor(syms::Vector{Symbol})
    parity = false
    counts = Dict{Symbol,Int}()
    for sym in syms
        if sym == Symbol("true")
            parity = !parity
        elseif sym == Symbol("false")
            continue
        else
            counts[sym] = get(counts, sym, 0) + 1
        end
    end

    vars = Symbol[]
    for (sym, count) in counts
        isodd(count) && push!(vars, sym)
    end

    isempty(vars) && return BooleanExpr(parity)

    if length(vars) == 1
        if parity
            # a ⊕ true = ¬a，直接用 NOT 表达更规范
            return BooleanExpr(_NOT_HEAD, [BooleanExpr(vars[1])])
        else
            return BooleanExpr(vars[1])
        end
    end

    parity && push!(vars, Symbol("true"))
    sort!(vars, by=String)
    return BooleanExpr(_XOR_HEAD, BooleanExpr.(vars))
end

function _expr_key(expr::BooleanExpr)
    expr.head == :var && return (expr.head, (expr.var,))
    return (expr.head, Tuple(arg.var for arg in expr.args))
end
