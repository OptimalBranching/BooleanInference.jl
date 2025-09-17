# This script is motivated by Zhongyi Ni

using Random
using JSON3
using ProblemReductions
using Gurobi
using JuMP
using BenchmarkTools
include("prime.jl")
include("factoring.jl")

"""
    circuit_from_factoring(m, n, N; use_constraints=true)

Build the CircuitSAT reduced from Factoring(m,n,N) and return:
- dict with metadata and gate-level truth tables
- also return (res, problem) if you need deeper handles
"""
function circuit_from_factoring(m::Int, n::Int, N::BigInt; use_constraints::Bool=true)
    fact = Factoring(m, n, N)
    res  = reduceto(CircuitSAT, fact)

    # Construct a CircuitSAT instance that exposes gate constraints.
    csat_problem = CircuitSAT(res.circuit.circuit; use_constraints)

    # Extract constraints (each is a gate with its local variables and allowed pattern)
    cons = constraints(csat_problem)
    nvars = ProblemReductions.num_variables(csat_problem)

    # Build a clean JSON-serializable object
    # specification is a Bool vector over {0,1}^arity in lexicographic order used by ProblemReductions
    gates = Vector{Any}(undef, length(cons))
    for (i, c) in enumerate(cons)
        gates[i] = Dict(
            "variables" => c.variables,            # 1-based indices into the global x[1:nvars]
            "specification" => collect(c.specification) # Bool array, true => allowed pattern
        )
    end

    obj = Dict(
        "type" => "CircuitSAT_Factoring",
        "m" => m,
        "n" => n,
        "N" => string(N),                # store as string to avoid JSON int size limits
        "num_variables" => nvars,
        # res.p / res.q are index vectors that pick out bit-positions of the two factors
        "p_indices" => res.p,
        "q_indices" => res.q,
        "gates" => gates
    )
    return obj, (res, csat_problem)
end

# ========== Dataset writer ==========

"""
    write_jsonl(io, obj)
Write one JSON object per line (JSONL).
"""
function write_jsonl(io::IO, obj)
    JSON3.write(io, obj)
    write(io, '\n')
end

"""
    sample_instance(m, n; kind="sat"|"unsat", nbits_override::Int=n+m)
Create one factoring-based circuit instance:
- kind="sat": choose N = a*b with ~m/n bits => satisfiable.
- kind="unsat": choose prime-like N with bit-length > (m+n) so no factors fit bit-widths.
Returns a JSON object of the circuit.
"""
function sample_instance(m::Int, n::Int; kind::String="sat", nbits_override::Int=m+n)
    if kind == "sat"
        a, b, N = semiprime(m, n)
        obj, _ = circuit_from_factoring(m, n, N; use_constraints=true)
        obj["label_sat"] = true
        obj["a"] = string(a)   # optional: keep hidden labels if you need supervision
        obj["b"] = string(b)
        return obj
    elseif kind == "unsat"
        # Pick an N that cannot be factored within m,n bits (e.g., too large)
        # So that any a,b with ≤ m,n bits cannot reach N exactly.
        N = prime_like(max(nbits_override, m + n + 1))
        obj, _ = circuit_from_factoring(m, n, N; use_constraints=true)
        obj["label_sat"] = false
        return obj
    else
        error("Unknown kind = $kind")
    end
end

"""
    build_dataset(path; configs, per_config=100, sat_ratio=0.5, rng=Random.GLOBAL_RNG)

Generate a JSONL dataset at `path` with mixed SAT/UNSAT circuit instances.
- `configs`: a vector of (m, n) tuples, e.g. [(16,16), (32,32)]
- `per_config`: how many samples per (m,n)
- `sat_ratio`: fraction of SAT cases; the rest will be UNSAT
"""
function build_dataset(path::AbstractString; 
                       configs::Vector{Tuple{Int,Int}}=[(16,16), (24,24), (32,32)],
                       per_config::Int=200,
                       sat_ratio::Float64=0.5,
                       rng::AbstractRNG=Random.GLOBAL_RNG)

    open(path, "w") do io
        for (m, n) in configs
            nsat = round(Int, per_config * sat_ratio)
            nuns = per_config - nsat

            # SAT cases
            for _ in 1:nsat
                obj = sample_instance(m, n; kind="sat")
                obj["id"] = "fact-$(m)x$(n)-sat-" * string(rand(rng, UInt32))
                write_jsonl(io, obj)
            end

            # UNSAT cases
            for _ in 1:nuns
                obj = sample_instance(m, n; kind="unsat", nbits_override=m+n+4)
                obj["id"] = "fact-$(m)x$(n)-unsat-" * string(rand(rng, UInt32))
                write_jsonl(io, obj)
            end
        end
    end
    @info "Wrote dataset to $path"
end

# ========= Callibration ==========

function callibrate()
    configs=[8,10,12,14,16,18,20]
    for b in configs
        @show b
        p, q, N = random_semiprime(b, b)
        t = @belapsed factoring($b, $b, $N)
        @info "Config: $b-- p: $p, q: $q, N: $N"
        @info "Time: $t"
    end    
end

callibrate()


# ========== Example run ==========
# Small quick dataset for sanity check
build_dataset("circuit_sat_factoring_small.jsonl"; 
              configs=[(8,8), (12,12)],
              per_config=20, 
              sat_ratio=0.5)

# Larger dataset (uncomment as needed)
# build_dataset("circuit_sat_factoring_medium.jsonl";
#               configs=[(16,16), (24,24), (32,32)],
#               per_config=500,
#               sat_ratio=0.5)