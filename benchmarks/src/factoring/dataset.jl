function deterministic_seed(config::FactoringConfig)
    content = "$(config.m)|$(config.n)"
    hash_bytes = sha256(content)
    return reinterpret(UInt64, hash_bytes[1:8])[1]
end

function generate_factoring_datasets(configs::Vector{FactoringConfig}; per_config::Int=100, include_solution::Bool=false, seed::Union{UInt64, Nothing}=nothing, force_regenerate::Bool=false)
    outdir = resolve_data_dir("factoring")
    isdir(outdir) || mkpath(outdir)

    paths = String[]
    generated_count = 0
    reused_count = 0

    for config in configs
        filename = filename_pattern(FactoringProblem, config)
        path = joinpath(outdir, filename)

        # Use provided seed or generate deterministic seed from config
        config_seed = isnothing(seed) ? deterministic_seed(config) : seed

        if !force_regenerate && isfile(path)
            @info "Reusing existing dataset: $path"
            push!(paths, path)
            reused_count += 1
            continue
        end

        @info "Generating new dataset: $path"
        @info "  Using seed: $config_seed, instances: $per_config"

        seeded_rng = Random.Xoshiro(config_seed)

        open(path, "w") do io
            for i in 1:per_config
                instance = generate_instance(FactoringProblem, config;
                                           rng=seeded_rng,
                                           include_solution=include_solution)

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

