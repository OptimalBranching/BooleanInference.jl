# ---------- Verilog codegen for Circuit ----------

# Make a Verilog-safe identifier from a Symbol (e.g., Symbol("##var#236") -> "__var_236")

sanitize_name(s::Symbol) = let raw = String(s)
    # replace non-alnum with underscore
    cleaned = replace(raw, r"[^A-Za-z0-9_]" => "_")
    # if starts with digit, prefix underscore
    startswith(cleaned, r"[0-9]") ? "_" * cleaned : cleaned
end

# Natural sort key: split alpha prefix and numeric suffix so p2 < p10
function _nat_key(s::Symbol)
    str = String(s)
    m = match(r"^([A-Za-z_]+)(\d+)$", str)
    if m === nothing
        return (str, -1)  # names without numeric suffix come first among same prefix
    else
        return (m.captures[1], parse(Int, m.captures[2]))
    end
end

is_true_sym(s::Symbol)  = s === Symbol("true")
is_false_sym(s::Symbol) = s === Symbol("false")

function verilog_expr(ex::BooleanExpr, rename::Dict{Symbol,String})
    if ex.head == :var
        s = ex.var
        return is_true_sym(s)  ? "1'b1" :
               is_false_sym(s) ? "1'b0" :
               rename[s]  # Regular variable
    end

    args = verilog_expr.(ex.args, Ref(rename))

    head = ex.head
    if head == :¬
        @assert length(args) == 1 "Unary NOT expects 1 argument"
        return "(~" * args[1] * ")"
    elseif head == :∧
        return "(" * join(args, " & ") * ")"
    elseif head == :∨
        return "(" * join(args, " | ") * ")"
    elseif head == :⊻
        return "(" * join(args, " ^ ") * ")"
    else
        error("Unsupported gate head: $head")
    end
end

# Gather symbol usage: defs (LHS outputs), uses (RHS variables), and all symbols
function collect_def_use(c::Circuit)
    defs = Symbol[]
    uses = Symbol[]
    for ex in c.exprs
        append!(defs, ex.outputs)
        extract_symbols!(ex.expr, uses)  # RHS variables (includes true/false which we'll drop later)
    end
    # drop boolean constants from uses
    filter!(s -> !(is_true_sym(s) || is_false_sym(s)), uses)
    return unique!(defs), unique!(uses)
end

# Infer module I/O and internal wires.
# - inputs: used but never assigned
# - sink outputs: assigned but never used later as inputs
# - internals: assigned but also used somewhere -> wires
function infer_io(c::Circuit; top_inputs::Union{Nothing,Vector{Symbol}}=nothing,
                              top_outputs::Union{Nothing,Vector{Symbol}}=nothing)
    defs, uses = collect_def_use(c)
    defs_set = Set(defs)
    uses_set = Set(uses)

    inferred_inputs  = collect(setdiff(uses_set, defs_set))
    sinks            = collect(setdiff(defs_set, uses_set))  # candidates for final outputs
    internals        = collect(intersect(defs_set, uses_set))

    inputs  = top_inputs  === nothing ? sort(inferred_inputs, by=_nat_key) : top_inputs
    outputs = top_outputs === nothing ? sort(sinks, by=_nat_key)          : top_outputs
    wires   = sort(setdiff(defs, outputs), by=_nat_key)  # everything assigned except chosen outputs
    return inputs, outputs, wires
end

# Build a stable rename dict for all symbols involved
function build_renames(sc::Circuit, inputs::Vector{Symbol}, outputs::Vector{Symbol}, wires::Vector{Symbol};
                       use_tensor_names::Bool=false, orig_to_simplified::Union{Nothing,Dict{Int,Int}}=nothing)
    all_syms = Symbol[]
    append!(all_syms, inputs, outputs, wires)
    # Also catch any remaining RHS-only variables (should be inputs already)
    extract_symbols!(sc, all_syms)
    # Remove constants
    filter!(s -> !(is_true_sym(s) || is_false_sym(s)), all_syms)
    unique!(all_syms)
    rename = Dict{Symbol,String}()

    if use_tensor_names && !isnothing(orig_to_simplified)
        # Build reverse mapping: symbol -> tensor index
        symbol_to_tensor = Dict{Symbol, Int}()
        for (simplified_idx, orig_idx) in orig_to_simplified
            if simplified_idx <= length(sc.exprs)
                expr = sc.exprs[simplified_idx]
                for o in expr.outputs
                    symbol_to_tensor[o] = orig_idx
                end
            end
        end

        # Rename based on tensor indices
        for s in all_syms
            if haskey(symbol_to_tensor, s)
                # This is a gate output, name it based on tensor index
                rename[s] = "w$(symbol_to_tensor[s])"
            else
                # This is an input or output, keep original sanitized name
                rename[s] = sanitize_name(s)
            end
        end
    else
        # Original behavior: sanitize names
        for s in all_syms
            rename[s] = sanitize_name(s)
        end
    end
    return rename
end

# --- constraint helpers: detect constant RHS and split constraints ---
is_bool_const(ex::BooleanExpr) = (ex.head == :var) && (is_true_sym(ex.var) || is_false_sym(ex.var))
const_val(ex::BooleanExpr) = ex.head == :var ? is_true_sym(ex.var) : error("not a const expr")

"""
Return:
  defs::Vector{Assignment}           # keep normal assignments
  constraints::Vector{Tuple{Symbol,Bool}}  # (signal, must_be_value)
We treat any assignment whose RHS is a boolean constant as a constraint rather than an assignment
(to avoid collapsing the logic when exporting to Verilog/AIG).
"""
function split_defs_and_constraints(sc::Circuit)
    defs = Assignment[]
    cons = Tuple{Symbol,Bool}[]
    for ex in sc.exprs
        if is_bool_const(ex.expr)
            # record constraints for *each* LHS symbol
            val = const_val(ex.expr)
            for o in ex.outputs
                push!(cons, (o, val))
            end
            # do NOT emit this as an assignment
        else
            push!(defs, ex)
        end
    end
    return defs, cons
end

function circuit_to_verilog(c::Circuit;
                             module_name::String="circuit",
                             top_inputs::Union{Nothing,Vector{Symbol}}=nothing,
                             top_outputs::Union{Nothing,Vector{Symbol}}=nothing,
                             satisfiable_when_high::Bool=true,
                             use_tensor_names::Bool=true)
    # Ensure simplified form (introduces one-op assignments and temps)
    sc = simple_form(c)

    # Split functional defs vs. constant constraints
    defs, constraints = split_defs_and_constraints(sc)

    inputs, outputs, wires = infer_io(sc; top_inputs=top_inputs, top_outputs=top_outputs)

    # If there are constraints like o = 0/1, we don't override o;
    # instead we add a new SAT output that encodes all constraints.
    has_sat = !isempty(constraints)
    if has_sat
        outputs = Symbol[:sat]
        def_syms, _ = collect_def_use(sc)
        wires = sort(setdiff(def_syms, outputs), by=_nat_key)
    end

    # Build mapping from original circuit expression index to simplified circuit expression
    orig_to_simplified = nothing
    if use_tensor_names
        orig_to_simplified = build_original_to_simplified_mapping(c, sc)
    end

    rename = build_renames(sc, inputs, outputs, wires;
                          use_tensor_names=use_tensor_names,
                          orig_to_simplified=orig_to_simplified)
    if has_sat
        rename[:sat] = "sat"
    end

    # Header: keep a clean, deterministic port order: inputs then outputs
    port_list = join([rename[s] for s in vcat(inputs, outputs)], ", ")

    lines = String[]
    push!(lines, "module $(sanitize_name(Symbol(module_name))) ($port_list);")

    # Declarations
    if !isempty(inputs)
        push!(lines, "  input "  * join(getindex.(Ref(rename), inputs),  ", ") * ";")
    end
    # outputs already include :sat if needed
    if !isempty(outputs)
        push!(lines, "  output " * join(getindex.(Ref(rename), outputs), ", ") * ";")
    end
    if !isempty(wires)
        push!(lines, "  wire "   * join(getindex.(Ref(rename), wires),   ", ") * ";")
    end
    push!(lines, "")  # blank line

    # Assignments for functional defs only
    for (idx, ex) in enumerate(defs)
        rhs = verilog_expr(ex.expr, rename)
        for o in ex.outputs
            oname = rename[o]
            push!(lines, "  assign $oname = $rhs;")
        end
    end

    # Encode constraints as a single SAT output: sat = ∧ (o == const)
    if has_sat
        if satisfiable_when_high
            # Normal polarity: sat=1 when all constraints satisfied
            terms = String[]
            for (o, val) in constraints
                on = rename[o]
                push!(terms, val ? on : "(~" * on * ")")
            end
            sat_rhs = isempty(terms) ? "1'b1" : "(" * join(terms, " & ") * ")"
        else
            # Inverted polarity: sat=0 when all constraints satisfied
            # Use OR logic: sat = (o != val_1) | (o != val_2) | ...
            # This is equivalent to ~((o == val_1) & (o == val_2) & ...)
            terms = String[]
            for (o, val) in constraints
                on = rename[o]
                # Invert each constraint check
                push!(terms, val ? "(~" * on * ")" : on)
            end
            sat_rhs = isempty(terms) ? "1'b0" : "(" * join(terms, " | ") * ")"
        end
        push!(lines, "  assign " * rename[:sat] * " = " * sat_rhs * ";")
    end

    push!(lines, "endmodule")
    return join(lines, "\n")
end

# Build a mapping from simplified expression index to original circuit expression index
# This function traces back through simple_form transformations to find the original expression
function build_original_to_simplified_mapping(c::Circuit, sc::Circuit)
    # For now, we'll use a simple heuristic:
    # Map each simplified expression to its index in the original circuit based on output symbol matching
    mapping = Dict{Int, Int}()

    # Build a map from output symbol to original expression index
    output_to_orig = Dict{Symbol, Int}()
    for (i, expr) in enumerate(c.exprs)
        for o in expr.outputs
            output_to_orig[o] = i
        end
    end

    # For each simplified expression, try to find its corresponding original expression
    for (j, sexpr) in enumerate(sc.exprs)
        # Check if any output symbol matches an original expression
        for o in sexpr.outputs
            if haskey(output_to_orig, o)
                mapping[j] = output_to_orig[o]
                break
            end
        end
        # If no match found, use the simplified index
        if !haskey(mapping, j)
            mapping[j] = j
        end
    end

    return mapping
end

# Convenience writer
function write_verilog(io::IO, c::Circuit; kwargs...)
    print(io, circuit_to_verilog(c; kwargs...))
end

function write_verilog(path::AbstractString, c::Circuit; kwargs...)
    open(path, "w") do io
        write_verilog(io, c; kwargs...)
    end
    return path
end
