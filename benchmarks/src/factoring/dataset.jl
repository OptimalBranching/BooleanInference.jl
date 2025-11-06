function dataset_metadata_hash(config::FactoringConfig, per_config::Int, seed::UInt64, include_solution::Bool)
    parts = [
        string(config.m),
        string(config.n),
        string(per_config),
        string(seed),
        string(include_solution)
    ]
    content = join(parts, "|")
    return bytes2hex(sha256(content))[1:16]
end

function deterministic_seed(config::FactoringConfig)
    content = "$(config.m)|$(config.n)"
    hash_bytes = sha256(content)
    return reinterpret(UInt64, hash_bytes[1:8])[1]
end

function check_dataset_compatibility(path::String, config::FactoringConfig, 
                                    per_config::Int, seed::UInt64, include_solution::Bool)
    if !isfile(path)
        return false
    end
    
    try
        instances = read_instances(FactoringProblem, path)
        isempty(instances) && return false
        
        if length(instances) != per_config
            @info "  Dataset size mismatch: expected $per_config, found $(length(instances))"
            return false
        end
        
        expected_hash = dataset_metadata_hash(config, per_config, seed, include_solution)
        if has_metadata(instances[1], expected_hash)
            @info "  Found compatible dataset: $path"
            return true
        else
            @info "  Dataset parameter mismatch: $path"
            return false
        end
    catch e
        @warn "  Error checking dataset: $e"
        return false
    end
end


function generate_factoring_datasets(configs::Vector{FactoringConfig}; 
                                    per_config::Int=100,
                                    include_solution::Bool=false,
                                    force_regenerate::Bool=false)
    
    outdir = resolve_data_dir("factoring")
    isdir(outdir) || mkpath(outdir)
    
    paths = String[]
    generated_count = 0
    reused_count = 0
    
    for config in configs
        filename = filename_pattern(FactoringProblem, config)
        path = joinpath(outdir, filename)
        
        seed = deterministic_seed(config)
        
        if !force_regenerate && check_dataset_compatibility(path, config, per_config, seed, include_solution)
            @info "Reusing existing dataset: $path"
            push!(paths, path)
            reused_count += 1
            continue
        end
        
        @info "Generating new dataset: $path"
        @info "  Using seed: $seed, instances: $per_config"
        
        seeded_rng = Random.Xoshiro(seed)
        metadata_hash = dataset_metadata_hash(config, per_config, seed, include_solution)
        
        open(path, "w") do io
            for i in 1:per_config
                instance = generate_instance(FactoringProblem, config; 
                                           rng=seeded_rng, 
                                           include_solution=include_solution)
                
                if i == 1
                    instance = add_metadata(instance; 
                                          metadata_hash=metadata_hash,
                                          generation_seed=seed,
                                          generation_timestamp=nothing)
                end
                
                write_instance(io, instance)
            end
        end
        
        @info "Generated dataset: $path"
        push!(paths, path)
        generated_count += 1
    end
    
    @info "Dataset generation complete: $generated_count generated, $reused_count reused"
    return paths
end

