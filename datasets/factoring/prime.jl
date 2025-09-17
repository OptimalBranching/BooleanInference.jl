using Primes

# ---------- Config ----------
const DEFAULT_TRIAL_BOUND = 20_000
const DEFAULT_THRESHOLD_BITS = 30  # use list-then-sample when nbits < 30

# ---------- Small-prime cache for trial division ----------
const SMALL_PRIMES_CACHE = Primes.primes(DEFAULT_TRIAL_BOUND)

# ========== Utilities ==========

function nbits_prime_list(nbits::Int)
    @assert nbits > 0 "nbits must be > 0"
    lo = 1 << (nbits - 1)
    hi = (1 << nbits) - 1
    return Primes.primes(lo, hi)
end

"""
    random_nbits_prime(nbits; rng=Random.GLOBAL_RNG, trial_bound=DEFAULT_TRIAL_BOUND,
                       threshold_bits=DEFAULT_THRESHOLD_BITS)

Sample a random prime of exactly `nbits` bits.
- If nbits < threshold_bits: enumerate the whole range, then sample uniformly.
- Otherwise: sample odd candidates in [2^(nbits-1), 2^nbits-1], trial-divide by small primes,
  then run `isprime`.
"""
function random_nbits_prime(nbits::Int;
                            rng::AbstractRNG=Random.GLOBAL_RNG,
                            trial_bound::Int=DEFAULT_TRIAL_BOUND,
                            threshold_bits::Int=DEFAULT_THRESHOLD_BITS)
    @assert nbits > 1 "nbits must be ≥ 2"

    # Path 1: small-bit exact list then sample
    if nbits < threshold_bits
        plist = nbits_prime_list(nbits)
        @assert !isempty(plist) "No primes found in the requested bit range."
        return BigInt(rand(rng, plist))
    end

    # Path 2: big-bit randomized sampling
    lo = BigInt(1) << (nbits - 1)
    hi = (BigInt(1) << nbits) - 1 
    small_ps = trial_bound == DEFAULT_TRIAL_BOUND ? SMALL_PRIMES_CACHE : Primes.primes(trial_bound)

    while true
        # sample an odd candidate
        x = rand(rng, lo:hi) | 1
        # quick reject if divisible by a small prime
        divisible = false
        for p in small_ps
            # stop early once p^2 > x
            if BigInt(p) * BigInt(p) > x
                break
            end
            if x % p == 0
                divisible = true
                break
            end
        end
        divisible && continue
        # probable prime test (GMP-backed)
        if isprime(x)
            return x
        end
    end
end


"""
    random_semiprime(nbits_a::Int, nbits_b::Int;
                     rng=Random.GLOBAL_RNG, distinct::Bool=true,
                     trial_bound::Int=DEFAULT_TRIAL_BOUND,
                     threshold_bits::Int=DEFAULT_THRESHOLD_BITS)

Generate a semiprime N = p * q.
- Ensures p and q are primes with the requested bit widths.
- If `distinct=true`, resamples until p ≠ q.
Returns (p::BigInt, q::BigInt, N::BigInt).
"""
function random_semiprime(nbits_a::Int, nbits_b::Int;
                          rng::AbstractRNG=Random.GLOBAL_RNG,
                          distinct::Bool=true,
                          trial_bound::Int=DEFAULT_TRIAL_BOUND,
                          threshold_bits::Int=DEFAULT_THRESHOLD_BITS)
    p = random_nbits_prime(nbits_a; rng, trial_bound, threshold_bits)
    q = random_nbits_prime(nbits_b; rng, trial_bound, threshold_bits)

    # loop-resample to enforce p ≠ q if requested and bit-widths equal
    if distinct && nbits_a == nbits_b
        while q == p
            q = random_nbits_prime(nbits_b; rng, trial_bound, threshold_bits)
        end
    end

    return p, q, p * q
end