import ProblemReductions: BooleanExpr, simple_form, extract_symbols!

const _TRUE_SYMBOL = Symbol("true")
const _FALSE_SYMBOL = Symbol("false")

@inline function get_unfixed_vars(doms::Vector{DomainMask})::Vector{Int}
    unfixed_vars = Int[]
    @inbounds for (i, dm) in enumerate(doms)
        if !is_fixed(dm)
            push!(unfixed_vars, i)
        end
    end
    return unfixed_vars
end

# Convenience: compute number of unfixed variables quickly.
@inline function count_unfixed(doms::Vector{DomainMask})::Int
    c::Int = 0
    @inbounds for dm in doms
        if !is_fixed(dm)
            c += 1
        end
    end
    return c
end

bits_to_int(v::Vector{Bool}) = sum(b << (i - 1) for (i, b) in enumerate(v))

@inline _is_boolean_constant(sym::Symbol) = (sym === _TRUE_SYMBOL) | (sym === _FALSE_SYMBOL)

function _rhs_symbols(expr::BooleanExpr)
    syms = Symbol[]
    extract_symbols!(expr, syms)
    filter!(s -> !_is_boolean_constant(s), syms)
    return unique!(syms)
end

"""
    circuit_output_distances(c::Circuit;
                             use_constraints::Bool=true,
                             unreachable_distance::Int=typemax(Int))

Return a vector whose `i`-th entry is the minimum gate distance from the `i`-th
symbol in `CircuitSAT(c).symbols` to any circuit output (defined as signals that
are assigned but never used as RHS fanins). Symbols that do not reach an output
are filled with `unreachable_distance`.
"""
function circuit_output_distances(c::Circuit;
                                  use_constraints::Bool=true,
                                  unreachable_distance::Int=typemax(Int))
    sc = simple_form(c)
    fanins = Dict{Symbol, Vector{Symbol}}()
    rhs_use_count = Dict{Symbol, Int}()

    for assign in sc.exprs
        rhs_syms = _rhs_symbols(assign.expr)
        for out in assign.outputs
            fanins[out] = rhs_syms
        end
        for sym in rhs_syms
            rhs_use_count[sym] = get(rhs_use_count, sym, 0) + 1
        end
    end

    sinks = Symbol[]
    for sym in keys(fanins)
        if !haskey(rhs_use_count, sym)
            push!(sinks, sym)
        end
    end

    dist = Dict{Symbol, Int}()
    queue = Symbol[]
    for sink in sinks
        dist[sink] = 0
        push!(queue, sink)
    end

    while !isempty(queue)
        node = popfirst!(queue)
        next_level = dist[node] + 1
        for parent in get(fanins, node, Symbol[])
            if next_level < get(dist, parent, typemax(Int))
                dist[parent] = next_level
                push!(queue, parent)
            end
        end
    end

    sat = CircuitSAT(c; use_constraints=use_constraints)
    distances = Vector{Int}(undef, length(sat.symbols))
    @inbounds for (i, sym) in enumerate(sat.symbols)
        distances[i] = get(dist, sym, unreachable_distance)
    end
    return distances
end
