const _TRUE_SYMBOL = Symbol("true")
const _FALSE_SYMBOL = Symbol("false")
const _XOR_SYMBOL = Symbol("\u22bb")

"""
    circuit_to_cnf(circuit::Circuit; simplify::Bool=true) -> (cnf, symbols)

Convert a `ProblemReductions.@circuit` circuit into CNF in DIMACS-style
`Vector{Vector{Int}}` form. Returns the CNF and the symbol order used for
variable indexing (1-based).

If `simplify=false`, the circuit is used as-is without calling `simple_form`.
This is useful when the circuit has already been simplified and you want to
preserve the symbol order.
"""
function circuit_to_cnf(circuit::Circuit; simplify::Bool=true)
    # Only simplify if requested - avoid re-simplifying already optimized circuits
    working_circuit = simplify ? simple_form(circuit) : circuit
    symbols = ProblemReductions.symbols(working_circuit)
    sym_to_var = Dict{Symbol, Int}(s => i for (i, s) in enumerate(symbols))
    cnf = Vector{Vector{Int}}()
    next_var = Ref(length(symbols))

    for assignment in working_circuit.exprs
        for out_sym in assignment.outputs
            out_var = sym_to_var[out_sym]
            add_equivalence!(cnf, out_var, assignment.expr, sym_to_var, next_var)
        end
    end

    return cnf, symbols
end

function symbol_value(sym::Symbol, sym_to_var::Dict{Symbol, Int})
    if sym == _TRUE_SYMBOL
        return true
    elseif sym == _FALSE_SYMBOL
        return false
    end
    return sym_to_var[sym]
end

function add_unit!(cnf::Vector{Vector{Int}}, lit::Int)
    push!(cnf, [lit])
end

function add_eq!(cnf::Vector{Vector{Int}}, out_var::Int, in_var::Int)
    out_var == in_var && return
    push!(cnf, [-out_var, in_var])
    push!(cnf, [out_var, -in_var])
end

function add_eq_neg!(cnf::Vector{Vector{Int}}, out_var::Int, in_var::Int)
    push!(cnf, [-out_var, -in_var])
    push!(cnf, [out_var, in_var])
end

function new_aux_var!(next_var::Base.RefValue{Int})
    next_var[] += 1
    return next_var[]
end

function add_xor_clauses!(cnf::Vector{Vector{Int}}, out_lit::Int, x::Int, y::Int)
    push!(cnf, [-out_lit, -x, -y])
    push!(cnf, [-out_lit, x, y])
    push!(cnf, [out_lit, -x, y])
    push!(cnf, [out_lit, x, -y])
end


function add_xor_chain!(
    cnf::Vector{Vector{Int}},
    out_var::Int,
    vars::Vector{Int},
    negate::Bool,
    next_var::Base.RefValue{Int},
)
    if length(vars) == 1
        if negate
            add_eq_neg!(cnf, out_var, vars[1])
        else
            add_eq!(cnf, out_var, vars[1])
        end
        return
    end

    if length(vars) == 2
        out_lit = negate ? -out_var : out_var
        add_xor_clauses!(cnf, out_lit, vars[1], vars[2])
        return
    end

    tmp = new_aux_var!(next_var)
    add_xor_clauses!(cnf, tmp, vars[1], vars[2])

    for i in 3:(length(vars) - 1)
        tmp2 = new_aux_var!(next_var)
        add_xor_clauses!(cnf, tmp2, tmp, vars[i])
        tmp = tmp2
    end

    out_lit = negate ? -out_var : out_var
    add_xor_clauses!(cnf, out_lit, tmp, vars[end])
end

function add_equivalence!(
    cnf::Vector{Vector{Int}},
    out_var::Int,
    expr::BooleanExpr,
    sym_to_var::Dict{Symbol, Int},
    next_var::Base.RefValue{Int},
)
    head = expr.head
    if head == :var
        val = symbol_value(expr.var, sym_to_var)
        if val isa Bool
            add_unit!(cnf, val ? out_var : -out_var)
        else
            add_eq!(cnf, out_var, val)
        end
        return
    elseif head == :¬
        arg = expr.args[1]
        val = symbol_value(arg.var, sym_to_var)
        if val isa Bool
            add_unit!(cnf, (!val) ? out_var : -out_var)
        else
            add_eq_neg!(cnf, out_var, val)
        end
        return
    elseif head == :∧
        lits = Int[]
        for arg in expr.args
            val = symbol_value(arg.var, sym_to_var)
            if val isa Bool
                if !val
                    add_unit!(cnf, -out_var)
                    return
                end
            else
                push!(lits, val)
            end
        end
        if isempty(lits)
            add_unit!(cnf, out_var)
            return
        end
        for lit in lits
            push!(cnf, [-out_var, lit])
        end
        push!(cnf, [out_var, (-l for l in lits)...])
        return
    elseif head == :∨
        lits = Int[]
        for arg in expr.args
            val = symbol_value(arg.var, sym_to_var)
            if val isa Bool
                if val
                    add_unit!(cnf, out_var)
                    return
                end
            else
                push!(lits, val)
            end
        end
        if isempty(lits)
            add_unit!(cnf, -out_var)
            return
        end
        for lit in lits
            push!(cnf, [out_var, -lit])
        end
        push!(cnf, [-out_var, lits...])
        return
    elseif head == _XOR_SYMBOL
        vars = Int[]
        parity = false
        for arg in expr.args
            val = symbol_value(arg.var, sym_to_var)
            if val isa Bool
                parity = xor(parity, val)
            else
                push!(vars, val)
            end
        end
        if isempty(vars)
            add_unit!(cnf, parity ? out_var : -out_var)
            return
        end
        add_xor_chain!(cnf, out_var, vars, parity, next_var)
        return
    end

    error("Unsupported boolean operator $(head) in circuit to CNF conversion.")
end
