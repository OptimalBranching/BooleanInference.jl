function dataset_metadata_hash(problem_type::Type{<:AbstractBenchmarkProblem}, 
                               config::AbstractProblemConfig,
                               per_config::Int, 
                               seed::UInt64,
                               include_solution::Bool)
    parts = [
        string(problem_type),
        string(config),
        string(per_config),
        string(seed),
        string(include_solution)
    ]
    content = join(parts, "|")
    return bytes2hex(sha256(content))[1:16]
end

function deterministic_seed(problem_type::Type{<:AbstractBenchmarkProblem}, 
                           config::AbstractProblemConfig)
    content = string(problem_type) * "|" * string(config)
    hash_bytes = sha256(content)
    return reinterpret(UInt64, hash_bytes[1:8])[1]
end

function check_dataset_compatibility(dataset_path::String,
                                   problem_type::Type{<:AbstractBenchmarkProblem},
                                   config::AbstractProblemConfig,
                                   per_config::Int,
                                   seed::UInt64,
                                   include_solution::Bool)
    if !isfile(dataset_path)
        return false
    end
    
    try
        lines = readlines(dataset_path)
        if isempty(lines)
            return false
        end
        
        if length(lines) != per_config
            @info "  Dataset size mismatch: expected $per_config instances, found $(length(lines))"
            return false
        end
        
        first_instance = JSON3.read(lines[1])
        expected_hash = dataset_metadata_hash(problem_type, config, per_config, seed, include_solution)
        
        if haskey(first_instance, "_metadata_hash")
            if first_instance["_metadata_hash"] == expected_hash
                @info "  Found compatible dataset: $dataset_path"
                return true
            else
                @info "  Dataset parameter mismatch: $dataset_path"
                return false
            end
        else
            @info "  Legacy dataset without metadata: $dataset_path"
            return false
        end
    catch e
        @warn "  Error checking dataset compatibility: $e"
        return false
    end
end

function generate_datasets(problem_type::Type{<:AbstractBenchmarkProblem}; 
                          configs::Vector{<:AbstractProblemConfig},
                          per_config::Int=100,
                          include_solution::Bool=false,
                          force_regenerate::Bool=false)
    
    outdir = resolve_data_dir(lowercase(string(problem_type)[1:end-7]))
    isdir(outdir) || mkpath(outdir)
    
    paths = String[]
    generated_count = 0
    reused_count = 0
    
    for config in configs
        filename = filename_pattern(problem_type, config)
        path = joinpath(outdir, filename)
        
        seed = deterministic_seed(problem_type, config)
        
        if !force_regenerate && check_dataset_compatibility(path, problem_type, config, per_config, seed, include_solution)
            @info "Reusing existing dataset: $path"
            push!(paths, path)
            reused_count += 1
            continue
        end
        
        @info "Generating new dataset: $path"
        @info "  Using deterministic seed: $seed"
        
        seeded_rng = Random.Xoshiro(seed)
        metadata_hash = dataset_metadata_hash(problem_type, config, per_config, seed, include_solution)
        
        open(path, "w") do io
            for i in 1:per_config
                instance = generate_instance(problem_type, config; rng=seeded_rng, include_solution=include_solution)
                
                if i == 1
                    instance = merge(instance, Dict(
                        "_metadata_hash" => metadata_hash,
                        "_generation_seed" => seed,
                        "_generation_timestamp" => string(now())
                    ))
                end
                
                JSON3.write(io, instance)
                write(io, '\n')
            end
        end
        
        @info "Generated dataset: $path (metadata hash: $metadata_hash)"
        push!(paths, path)
        generated_count += 1
    end
    
    @info "Dataset generation complete: $(generated_count) generated, $(reused_count) reused in: $outdir"
    return paths
end

