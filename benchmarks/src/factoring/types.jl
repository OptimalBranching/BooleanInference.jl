struct FactoringProblem <: AbstractBenchmarkProblem end

struct FactoringConfig <: AbstractProblemConfig
    m::Int
    n::Int
end

struct FactoringInstance <: AbstractInstance
    m::Int
    n::Int
    N::BigInt
    id::String
    # Optional solution fields
    p::Union{BigInt, Nothing}
    q::Union{BigInt, Nothing}
    # Optional metadata fields
    metadata_hash::Union{String, Nothing}
    generation_seed::Union{UInt64, Nothing}
    generation_timestamp::Union{String, Nothing}
    
    function FactoringInstance(m::Int, n::Int, N::Integer, id::String; 
                               p=nothing, q=nothing,
                               metadata_hash=nothing, 
                               generation_seed=nothing,
                               generation_timestamp=nothing)
        new(m, n, BigInt(N), id, 
            isnothing(p) ? nothing : BigInt(p),
            isnothing(q) ? nothing : BigInt(q),
            metadata_hash, generation_seed, generation_timestamp)
    end
end


# ----------------------------------------
# Dataset I/O Implementation (JSON format)
# ----------------------------------------

# Write a single instance to IO (JSON format)
function write_instance(io::IO, instance::FactoringInstance)
    obj = Dict{String, Any}(
        "m" => instance.m,
        "n" => instance.n,
        "N" => string(instance.N),
        "id" => instance.id
    )
    
    if !isnothing(instance.p)
        obj["p"] = string(instance.p)
    end
    if !isnothing(instance.q)
        obj["q"] = string(instance.q)
    end
    if !isnothing(instance.metadata_hash)
        obj["_metadata_hash"] = instance.metadata_hash
    end
    if !isnothing(instance.generation_seed)
        obj["_generation_seed"] = instance.generation_seed
    end
    if !isnothing(instance.generation_timestamp)
        obj["_generation_timestamp"] = instance.generation_timestamp
    end
    
    JSON3.write(io, obj)
    write(io, '\n')
end

# Read instances from file (JSON format)
function read_instances(::Type{FactoringProblem}, path::AbstractString)
    instances = FactoringInstance[]
    open(path, "r") do io
        for line in eachline(io)
            isempty(strip(line)) && continue
            data = JSON3.read(line)
            
            m = data["m"]
            n = data["n"]
            N = parse(BigInt, data["N"])
            id = data["id"]
            
            p = haskey(data, "p") ? parse(BigInt, data["p"]) : nothing
            q = haskey(data, "q") ? parse(BigInt, data["q"]) : nothing
            metadata_hash = haskey(data, "_metadata_hash") ? data["_metadata_hash"] : nothing
            generation_seed = haskey(data, "_generation_seed") ? UInt64(data["_generation_seed"]) : nothing
            generation_timestamp = haskey(data, "_generation_timestamp") ? data["_generation_timestamp"] : nothing
            
            instance = FactoringInstance(m, n, N, id; 
                                        p=p, q=q,
                                        metadata_hash=metadata_hash,
                                        generation_seed=generation_seed,
                                        generation_timestamp=generation_timestamp)
            push!(instances, instance)
        end
    end
    return instances
end

# Check metadata
function has_metadata(instance::FactoringInstance, expected_hash::String)
    return !isnothing(instance.metadata_hash) && instance.metadata_hash == expected_hash
end