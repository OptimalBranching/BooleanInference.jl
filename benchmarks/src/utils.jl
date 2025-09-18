# Generic benchmark utilities

"""
    resolve_data_dir(parts...)
Resolve data directory under benchmark package root.
"""
function resolve_data_dir(parts::AbstractString...)
    base = normpath(joinpath(@__DIR__, ".."))
    dir = joinpath(base, "data", parts...)
    isdir(dir) || mkpath(dir)
    return dir
end

"""
    write_jsonl(io, obj)
Write one JSON object per line (JSONL format).
"""
function write_jsonl(io::IO, obj)
    JSON3.write(io, obj)
    write(io, '\n')
end

"""
    read_jsonl(path)
Read JSONL file and return vector of parsed objects.
"""
function read_jsonl(path::AbstractString)
    objs = Any[]
    open(path, "r") do io
        for line in eachline(io)
            isempty(strip(line)) && continue
            push!(objs, JSON3.read(line))
        end
    end
    return objs
end

"""
    build_datasets(; outdir, generator, filename_fn, configs, per_config=100, rng)
Build separate dataset files for each config (one file per config).
"""
function build_datasets(; 
                        outdir::AbstractString,
                        generator,
                        filename_fn,
                        configs,
                        per_config::Int=100,
                        rng::AbstractRNG=Random.GLOBAL_RNG)
    isdir(outdir) || mkpath(outdir)
    paths = String[]
    for cfg in configs
        path = joinpath(outdir, filename_fn(cfg))
        open(path, "w") do io
            for _ in 1:per_config
                obj = generator(cfg; rng=rng)
                write_jsonl(io, obj)
            end
        end
        @info "Generated dataset: $path"
        push!(paths, path)
    end
    @info "Generated $(length(paths)) dataset files in: $outdir"
    return paths
end

"""
    benchmark_configs(configs; trial_fn, samples_per_config=5)
Generic benchmark runner for different configurations.
"""
function benchmark_configs(configs; trial_fn, samples_per_config::Int=5)
    results = []
    for cfg in configs
        @info "Benchmarking config: $cfg"
        times = Float64[]
        for _ in 1:samples_per_config
            t = @belapsed $trial_fn($cfg)
            push!(times, t)
        end
        push!(results, Dict(
            "config" => cfg,
            "times" => times,
            "mean_time" => sum(times) / length(times),
            "min_time" => minimum(times)
        ))
    end
    return results
end