struct FactoringProblem <: AbstractBenchmarkProblem end

struct FactoringConfig <: AbstractProblemConfig
    m::Int
    n::Int
end

struct FactoringInstance <: AbstractInstance
    m::Int
    n::Int
    N::BigInt
    # Optional solution fields
    p::Union{BigInt, Nothing}
    q::Union{BigInt, Nothing}

    function FactoringInstance(m::Int, n::Int, N::Integer;
                               p=nothing, q=nothing)
        new(m, n, BigInt(N),
            isnothing(p) ? nothing : BigInt(p),
            isnothing(q) ? nothing : BigInt(q))
    end
end


# ----------------------------------------
# Dataset I/O Implementation (Text format)
# ----------------------------------------
# Format: m n N [p q]
# Each line contains space-separated values:
# - m, n: bit sizes of the two prime factors
# - N: the semiprime to factor
# - p, q: optional prime factors (only if include_solution=true)
#
# Example without solution:
#   10 10 893077
#   10 10 742891
#
# Example with solution:
#   10 10 893077 971 919
#   10 10 742891 883 841

# Write a single instance to IO (text format)
function write_instance(io::IO, instance::FactoringInstance)
    print(io, instance.m, " ", instance.n, " ", instance.N)

    if !isnothing(instance.p) && !isnothing(instance.q)
        print(io, " ", instance.p, " ", instance.q)
    end

    println(io)
end

# Read instances from file (text format)
function read_instances(::Type{FactoringProblem}, path::AbstractString)
    instances = FactoringInstance[]
    open(path, "r") do io
        for line in eachline(io)
            isempty(strip(line)) && continue

            parts = split(strip(line))
            length(parts) < 3 && continue

            m = parse(Int, parts[1])
            n = parse(Int, parts[2])
            N = parse(BigInt, parts[3])

            # Check if solution is included
            p = length(parts) >= 5 ? parse(BigInt, parts[4]) : nothing
            q = length(parts) >= 5 ? parse(BigInt, parts[5]) : nothing

            instance = FactoringInstance(m, n, N; p=p, q=q)
            push!(instances, instance)
        end
    end
    return instances
end