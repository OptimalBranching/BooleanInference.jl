using Random
using Primes
using JSON3
using SHA: bytes2hex, sha1
using BooleanInference
using JuMP
using Gurobi
using ..BooleanInferenceBenchmarks: resolve_data_dir, AbstractSolver

# Define solver types for factoring problems
"""
BooleanInference solver - uses the original BooleanInference.solve_factoring method
"""
struct BooleanInferenceSolver <: AbstractSolver end

"""
Integer Programming solver - uses JuMP with Gurobi optimizer
"""
struct IPSolver <: AbstractSolver 
    optimizer::Any
    env::Any
    
    function IPSolver(optimizer=Gurobi.Optimizer, env=nothing)
        new(optimizer, env)
    end
end

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

# Implement solve_instance with different solvers
function solve_instance(::Type{FactoringProblem}, instance, solver::BooleanInferenceSolver)
    m = instance["m"]
    n = instance["n"]
    N = parse(Int, instance["N"])
    return BooleanInference.solve_factoring(m, n, N)
end

function solve_instance(::Type{FactoringProblem}, instance, solver::IPSolver)
    m = instance["m"]
    n = instance["n"]
    N = parse(Int, instance["N"])
    return factoring(m, n, N; optimizer=solver.optimizer, env=solver.env)
end

"""
    verify_solution(::Type{FactoringProblem}, instance, result)

Verify that the factoring result is correct.
"""
function verify_solution(::Type{FactoringProblem}, instance, result)
    try
        N = parse(Int, instance["N"])
        
        # Handle different result formats
        if result isa Tuple && length(result) == 2
            p, q = result
        elseif result isa Dict
            p = get(result, "p", nothing)
            q = get(result, "q", nothing)
            if p === nothing || q === nothing
                return false
            end
        elseif hasfield(typeof(result), :p) && hasfield(typeof(result), :q)
            p = result.p
            q = result.q
        else
            @warn "Unknown result format: $(typeof(result))"
            return false
        end
        
        # Verify the factorization
        if p * q == N
            return true
        else
            @warn "Incorrect factorization: $p × $q = $(p*q) ≠ $N"
            return false
        end
    catch e
        @warn "Error verifying solution: $e"
        return false
    end
end

function run_full_benchmark(::Type{FactoringProblem},
                           input_configs::Union{Vector{Tuple{Int,Int}}, Nothing}=nothing;
                           dataset_per_config::Int=50,
                           solver=nothing)
    
    if isnothing(input_configs)
        configs = default_configs(FactoringProblem)
    else
        configs = [config(FactoringProblem, config_item) for config_item in input_configs]
    end
        
    results = benchmark_backend(FactoringProblem, configs; dataset_per_config=dataset_per_config, solver=solver)
    
    return results
end


function problem_id(::Type{FactoringProblem}, config::FactoringConfig, N::Integer)
    h = bytes2hex(sha1(string(config.m, "|", config.n, "|", N)))
    return h[1:16]  # 16-char prefix
end

function default_configs(::Type{FactoringProblem})
    return FactoringConfig[
        FactoringConfig(10, 10),
        FactoringConfig(12, 12),
        FactoringConfig(14, 14),
     ]
end

function config(::Type{FactoringProblem}, params::Tuple{Int,Int})
    return FactoringConfig(params[1], params[2])
end

function filename_pattern(::Type{FactoringProblem}, config::FactoringConfig)
    return "numbers_$(config.m)x$(config.n).jsonl"
end

# Solver interface implementations
function available_solvers(::Type{FactoringProblem})
    return [BooleanInferenceSolver(), IPSolver()]
end

function default_solver(::Type{FactoringProblem})
    return BooleanInferenceSolver()
end

function solver_name(::BooleanInferenceSolver)
    return "BooleanInference"
end

function solver_name(solver::IPSolver)
    return "IP-$(solver.optimizer)"
end
