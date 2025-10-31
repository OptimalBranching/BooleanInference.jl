function random_prime_bits(bits::Int; rng=Random.GLOBAL_RNG)
    if bits <= 1
        return 2
    end
    min_val = 2^(bits-1)
    max_val = 2^bits - 1
    for _ in 1:1000
        candidate = rand(rng, min_val:max_val)
        if candidate % 2 == 0
            candidate += 1
        end
        if isprime(candidate)
            return candidate
        end
    end
    candidate = rand(rng, min_val:max_val)
    return nextprime(candidate)
end

function random_semiprime(m::Int, n::Int; rng=Random.GLOBAL_RNG, distinct::Bool=false)
    p = random_prime_bits(m; rng)
    q = random_prime_bits(n; rng)
    if distinct && p == q
        while q == p
            q = random_prime_bits(n; rng)
        end
    end
    N = p * q
    return p, q, N
end

function generate_instance(::Type{FactoringProblem}, config::FactoringConfig; 
                          rng::AbstractRNG=Random.GLOBAL_RNG, 
                          include_solution::Bool=false)
    p, q, N = random_semiprime(config.m, config.n; rng=rng, distinct=true)
    id = problem_id(config, N)
    
    return FactoringInstance(
        config.m, config.n, N, id;
        p = include_solution ? p : nothing,
        q = include_solution ? q : nothing
    )
end

# Helper function to add metadata to an instance
function add_metadata(instance::FactoringInstance; 
                     metadata_hash=nothing, 
                     generation_seed=nothing,
                     generation_timestamp=nothing)
    return FactoringInstance(
        instance.m, instance.n, instance.N, instance.id;
        p=instance.p, q=instance.q,
        metadata_hash=metadata_hash,
        generation_seed=generation_seed,
        generation_timestamp=generation_timestamp
    )
end

