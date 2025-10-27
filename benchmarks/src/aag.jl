
# ========== Types ==========
"""
AIG container using AIGER literals (non-negative Ints).
All fields store AIGER literals directly.
- inputs:  even literals for primary inputs
- latches: vector of (q, d, init) where init ∈ (0,1,2) (2 = unknown).
- outputs: literals driving primary outputs
- ands:    vector of (lhs, rhs0, rhs1) for AND nodes
"""
struct AIG
    inputs::Vector{Int}
    latches::Vector{NTuple{3,Int}}  # (q, d, init)
    outputs::Vector{Int}
    ands::Vector{NTuple{3,Int}}     # (lhs, rhs0, rhs1)
    symbols::Dict{Tuple{Char,Int},String}  # ('i'/'l'/'o', idx) -> name
    comments::Vector{String}
end

AIG() = AIG(Int[], NTuple{3,Int}[], Int[], NTuple{3,Int}[], Dict{Tuple{Char,Int},String}(), String[])

# ========== Literal helpers ==========
"Build literal from var id (>=0) and neg flag."
lit(var::Int; neg::Bool=false) = var < 0 ? throw(ArgumentError("var<0")) : (var << 1) | (neg ? 1 : 0)
"Return variable id (>=0) for a literal."
var(l::Int) = l >>> 1
"True if literal is negated."
isneg(l::Int) = (l & 1) == 1
"Constant literals."
const_false() = 0
const_true() = 1

# ========== Parsing (.aag) ==========
"""
Read an .aag file (IO or path) into AIG.
Supports symbols (i/l/o lines) and comment section starting with `c`.
Latch line may be `q d` or `q d init`.
"""
function read_aag(io::IO)::AIG
    aig = AIG()
    # 1) header
    header = ""
    while !eof(io)
        header = strip(readline(io))
        isempty(header) && continue
        startswith(header, "c ") && break # unlikely, but guard
        break
    end
    parts = split(header)
    @assert !isempty(parts) "Empty file"
    @assert parts[1] == "aag" "Only ASCII AIGER (aag) is supported by this reader"
    @assert length(parts) >= 6 "Header must be: aag M I L O A"
    M = parse(Int, parts[2]); I = parse(Int, parts[3]); L = parse(Int, parts[4])
    O = parse(Int, parts[5]); A = parse(Int, parts[6])

    # 2) sections: I, L, O, A (strict counts)
    inputs = Int[]
    for _ in 1:I
        l = parse(Int, strip(readline(io)))
        push!(inputs, l)
    end

    latches = NTuple{3,Int}[]
    for _ in 1:L
        line = split(strip(readline(io)))
        @assert length(line) >= 2 "Latch line needs at least q d"
        q  = parse(Int, line[1])
        d  = parse(Int, line[2])
        init = length(line) >= 3 ? parse(Int, line[3]) : 2 # 2 = unknown
        push!(latches, (q, d, init))
    end

    outputs = Int[]
    for _ in 1:O
        l = parse(Int, strip(readline(io)))
        push!(outputs, l)
    end

    ands = NTuple{3,Int}[]
    for _ in 1:A
        line = split(strip(readline(io)))
        @assert length(line) == 3 "AND line must be lhs rhs0 rhs1"
        lhs  = parse(Int, line[1])
        r0   = parse(Int, line[2])
        r1   = parse(Int, line[3])
        push!(ands, (lhs, r0, r1))
    end

    # 3) optional symbol table + comments
    symbols = Dict{Tuple{Char,Int},String}()
    comments = String[]
    # A symbol line starts with: i / l / o  then index then name (rest of line)
    # The comments section starts with a single line "c" and then arbitrary lines.
    # We'll read remaining lines and split.
    symphase = true
    while !eof(io)
        line = readline(io)
        sline = strip(line)
        if symphase && sline == "c"
            symphase = false
            continue
        end
        if symphase
            if isempty(sline)
                continue
            end
            kind = sline[1]
            if kind in ('i','l','o')
                body = strip(sline[2:end])
                sp = findfirst(isspace, body)
                if sp === nothing
                    # no name?
                    idx = parse(Int, body)
                    symbols[(kind, idx)] = ""
                else
                    idx = parse(Int, strip(body[1:sp-1]))
                    name = strip(body[sp+1:end])
                    symbols[(kind, idx)] = name
                end
            else
                # Unknown line in symbol phase; ignore
            end
        else
            push!(comments, line)  # preserve as-is (may contain blanks)
        end
    end

    # Basic sanity (not exhaustive)
    _check_even_literals(inputs, "inputs")
    for (q,d,_) in latches
        @assert iseven(q) "Latch q must be an even literal"
        # d can be any literal
    end
    for (lhs, r0, r1) in ands
        @assert iseven(lhs) "AND lhs must be an even literal"
        # r0,r1 can be any literal; usually ordered by aiger rule, but we don't enforce
    end

    return AIG(inputs, latches, outputs, ands, symbols, comments)
end

read_aag(path::AbstractString) = open(read_aag, path, "r")

function _check_even_literals(v::Vector{Int}, what::AbstractString)
    for l in v
        @assert iseven(l) "$what must contain even literals; got $l"
    end
end

# ========== Writing (.aag) ==========
"""
Write an AIG to .aag (IO or path). If `M` is not provided, it is computed
as the maximum variable id appearing anywhere.
Preserves symbols/comments stored in `aig`.
"""
function write_aag(io::IO, aig::AIG; M::Union{Nothing,Int}=nothing)
    inputs, latches, outputs, ands = aig.inputs, aig.latches, aig.outputs, aig.ands
    I, L, O, A = length(inputs), length(latches), length(outputs), length(ands)
    maxvar = 0
    for l in inputs;  maxvar = max(maxvar, var(l)); end
    for (q,d,_) in latches; maxvar = max(maxvar, var(q), var(d)); end
    for l in outputs; maxvar = max(maxvar, var(l)); end
    for (lhs,r0,r1) in ands; maxvar = max(maxvar, var(lhs), var(r0), var(r1)); end
    M_ = isnothing(M) ? maxvar : M
    println(io, "aag $M_ $I $L $O $A")
    for l in inputs;  println(io, l); end
    for (q,d,init) in latches
        if init == 2
            println(io, "$q $d")
        else
            println(io, "$q $d $init")
        end
    end
    for l in outputs; println(io, l); end
    for (lhs,r0,r1) in ands; println(io, "$lhs $r0 $r1"); end
    # symbols
    for ((k,idx), name) in aig.symbols
        k ∈ ('i','l','o') || continue
        println(io, string(k), idx, " ", name)
    end
    # comments
    println(io, "c")
    for line in aig.comments
        print(io, line)  # already contains newline if it had
        endswith(line, "\n") || println(io)
    end
end

write_aag(path::AbstractString, aig::AIG; kwargs...) = open(io->write_aag(io, aig; kwargs...), path, "w")

# ========== Small utils ==========
"Return a human summary."
function summary(aig::AIG)
    I = length(aig.inputs); L = length(aig.latches); O = length(aig.outputs); A = length(aig.ands)
    maxv = 0
    for l in vcat(aig.inputs, aig.outputs)
        maxv = max(maxv, var(l))
    end
    for (q,d,_) in aig.latches
        maxv = max(maxv, var(q), var(d))
    end
    for (lhs,r0,r1) in aig.ands
        maxv = max(maxv, var(lhs), var(r0), var(r1))
    end
    return (; I, L, O, A, maxvar=maxv)
end

export AIG, read_aag, write_aag, lit, var, isneg, const_false, const_true, summary
