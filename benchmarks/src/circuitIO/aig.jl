# -----------------------------
# Minimal AAG (ASCII AIGER) reader
# -----------------------------
# Supports: header "aag M I L O A", I inputs, L latches (L must be 0 here),
# O outputs (as literals), A AND gates (lhs rhs0 rhs1).
# Literals: lit = 2*var + is_neg; even = positive; odd = negation.
#
# We deliberately keep a tiny parser here for robustness & no deps.

struct AIG
    inputs::Vector{Int}                 # even literals
    latches::Vector{NTuple{3,Int}}      # (q, d, init) -- we disallow L>0 below
    outputs::Vector{Int}                # any literals
    ands::Vector{NTuple{3,Int}}         # (lhs, rhs0, rhs1), lhs must be even
end

# Helpers for literals
varid(l::Int) = l >>> 1
isneg(l::Int) = (l & 1) == 1

function read_aag(path::AbstractString)::AIG
    open(path, "r") do io
        # header
        header = strip(readline(io))
        startswith(header, "aig ") && error("Got binary 'aig' header. Convert to ASCII: `aigtoaig -a in.aig > out.aag`.")
        @assert startswith(header, "aag ") "Unrecognized header (need 'aag ...')"
        parts = split(header)
        @assert length(parts) >= 6 "Header must be: aag M I L O A"
        M = parse(Int, parts[2]); I = parse(Int, parts[3]); L = parse(Int, parts[4])
        O = parse(Int, parts[5]); A = parse(Int, parts[6])

        inputs  = [parse(Int, strip(readline(io))) for _ in 1:I]
        latches = NTuple{3,Int}[]
        for _ in 1:L
            toks = split(strip(readline(io)))
            q  = parse(Int, toks[1]); d = parse(Int, toks[2])
            init = length(toks) >= 3 ? parse(Int, toks[3]) : 2
            push!(latches, (q, d, init))
        end
        outputs = [parse(Int, strip(readline(io))) for _ in 1:O]
        ands    = NTuple{3,Int}[]
        for _ in 1:A
            toks = split(strip(readline(io)))
            lhs = parse(Int, toks[1]); r0 = parse(Int, toks[2]); r1 = parse(Int, toks[3])
            push!(ands, (lhs, r0, r1))
        end

        # Basic sanity
        for l in inputs
            @assert iseven(l) "Input literal must be even, got $l"
        end
        for (lhs, _, _) in ands
            @assert iseven(lhs) "AND lhs must be even, got $lhs"
        end

        return AIG(inputs, latches, outputs, ands)
    end
end

# -----------------------------
# Name mapping & literal → expression-string
# -----------------------------
# We will generate a @circuit block as a string then `Meta.parse` + `eval`.
# This avoids touching internal Assignment types.

"""
Turn an AIG var id to a Julia symbol name used in @circuit.
We prefix with `n_` to avoid accidental name clashes.
"""
varname(v::Int) = Symbol("n_", string(v))

"""
Literal -> expression snippet string for @circuit:
- 0 -> false
- 1 -> true
- even -> n_<var>
- odd  -> ¬(n_<var>)
"""
function lit_str(l::Int)
    if l == 0
        return "false"
    elseif l == 1
        return "true"
    else
        v = varid(l)
        nm = string(varname(v))
        return isneg(l) ? "¬($nm)" : nm
    end
end

# -----------------------------
# AIG → ProblemReductions.Circuit (combinational)
# -----------------------------
"""
Build a ProblemReductions.Circuit from an AIG (no latches allowed).
- Each AND gate (lhs, r0, r1) becomes:  n_<lhsvar> = ∧(expr(r0), expr(r1))
- Each primary output becomes:          out<i>     = expr(lit)
Inputs do not need explicit assignments; they are just symbols used by gates.
"""
function aig_to_circuit(aig::AIG; output_prefix::AbstractString="out")
    if !isempty(aig.latches)
        error("This converter handles *combinational* circuits only (L=0). Found L=$(length(aig.latches)).")
    end

    # Collect all lhs var ids to ensure their symbols are bound in circuit order
    # AIGER usually guarantees ANDs are topologically ordered by growing lhs.
    assigns = String[]

    # AND gates
    for (lhs, r0, r1) in aig.ands
        lhs_nm = string(varname(varid(lhs)))
        push!(assigns, "$lhs_nm = ∧($(lit_str(r0)), $(lit_str(r1)))")
    end

    # Outputs: give them stable names
    for (i, l) in enumerate(aig.outputs)
        outnm = Symbol(output_prefix, "_", i)
        push!(assigns, string(outnm, " = ", lit_str(l)))
    end

    src = IOBuffer()
    println(src, "ProblemReductions.@circuit begin")
    for a in assigns
        println(src, "  ", a)
    end
    println(src, "end")
    code_str = String(take!(src))

    # Evaluate macro call to get a `Circuit`
    # This is the public, documented entry: @circuit returns a Circuit.  [oai_citation:1‡giggleliu.github.io](https://giggleliu.github.io/ProblemReductions.jl/dev/rules/spinglass_sat/)
    return Base.invokelatest(eval, Meta.parse(code_str))
end

