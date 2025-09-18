using Random
using Primes
using JSON3
using SHA: bytes2hex, sha1
using BooleanInference
using ..BooleanInferenceBenchmarks: resolve_data_dir

# Prime generation utilities
function random_semiprime(m::Int, n::Int; rng=Random.GLOBAL_RNG, distinct::Bool=false)
    # Generate two random primes of approximately m and n bits
    p = random_prime_bits(m; rng)
    q = random_prime_bits(n; rng)
    
    if distinct && p == q
        # If they're the same and we want distinct, regenerate q
        while q == p
            q = random_prime_bits(n; rng)
        end
    end
    
    N = p * q
    return p, q, N
end

function random_prime_bits(bits::Int; rng=Random.GLOBAL_RNG)
    # Generate a random prime with approximately 'bits' bits
    if bits <= 1
        return 2
    end
    
    # Range for n-bit numbers: 2^(n-1) to 2^n - 1
    min_val = 2^(bits-1)
    max_val = 2^bits - 1
    
    # Find a prime in this range
    for _ in 1:1000  # Max attempts
        candidate = rand(rng, min_val:max_val)
        if candidate % 2 == 0
            candidate += 1  # Make it odd
        end
        
        if isprime(candidate)
            return candidate
        end
    end
    
    # Fallback: use nextprime
    candidate = rand(rng, min_val:max_val)
    return nextprime(candidate)
end

"""
Factoring problem type.
"""
struct FactoringProblem <: AbstractBenchmarkProblem end

"""
Configuration for factoring problems.
"""
struct FactoringConfig <: AbstractProblemConfig
    m::Int  # bits for first factor
    n::Int  # bits for second factor
end

# Implement the interface for FactoringProblem

function generate_instance(::Type{FactoringProblem}, config::FactoringConfig; 
                          rng::AbstractRNG=Random.GLOBAL_RNG, 
                          include_solution::Bool=false)
    p, q, N = random_semiprime(config.m, config.n; rng=rng, distinct=true)
    
    instance = Dict(
        "m" => config.m,
        "n" => config.n,
        "N" => string(N),
        "id" => problem_id(FactoringProblem, config, N)
    )
    # include the solution in the dataset if requested
    if include_solution
        instance["p"] = string(p)
        instance["q"] = string(q)
    end
    
    return instance
end

function solve_instance(::Type{FactoringProblem}, instance)
    m = instance["m"]
    n = instance["n"]
    # sN = instance["N"]
    # N = something(tryparse(Int, sN), parse(BigInt, sN))
    N = parse(Int, instance["N"])  # Use Int is enough.
    return BooleanInference.solve_factoring(m, n, N)
end

function problem_id(::Type{FactoringProblem}, config::FactoringConfig, N::Integer)
    h = bytes2hex(sha1(string(config.m, "|", config.n, "|", N)))
    return h[1:16]  # 16-char prefix
end

function default_configs(::Type{FactoringProblem})
    return [
        FactoringConfig(10, 10),
        FactoringConfig(12, 12),
        FactoringConfig(14, 14),
        FactoringConfig(16, 16)
    ]
end

function filename_pattern(::Type{FactoringProblem}, config::FactoringConfig)
    return "numbers_$(config.m)x$(config.n).jsonl"
end
