# ============================================================================
# problems.jl - Problem loading and dataset management
# ============================================================================

# ============================================================================
# Factoring
# ============================================================================

function read_factoring_instances(path::AbstractString)
    instances = FactoringInstance[]
    open(path, "r") do io
        for line in eachline(io)
            isempty(strip(line)) && continue
            parts = split(strip(line))
            length(parts) < 3 && continue
            m, n, N = parse(Int, parts[1]), parse(Int, parts[2]), parse(BigInt, parts[3])
            p = length(parts) >= 5 ? parse(BigInt, parts[4]) : nothing
            q = length(parts) >= 5 ? parse(BigInt, parts[5]) : nothing
            push!(instances, FactoringInstance(m, n, N; p, q))
        end
    end
    instances
end

function generate_factoring_instance(m::Int, n::Int; rng=Random.GLOBAL_RNG)
    p = Primes.nextprime(rand(rng, 2^(m-1):2^m-1))
    q = Primes.nextprime(rand(rng, 2^(n-1):2^n-1))
    FactoringInstance(m, n, p * q; p, q)
end

function generate_factoring_datasets(configs::Vector{FactoringConfig};
    per_config::Int=100,
    include_solution::Bool=true,
    force_regenerate::Bool=false)
    paths = String[]
    for cfg in configs
        dir = resolve_data_dir("factoring")
        path = joinpath(dir, "numbers_$(cfg.m)x$(cfg.n).txt")

        if isfile(path) && !force_regenerate
            push!(paths, path)
            continue
        end

        open(path, "w") do io
            for _ in 1:per_config
                inst = generate_factoring_instance(cfg.m, cfg.n)
                print(io, "$(inst.m) $(inst.n) $(inst.N)")
                include_solution && print(io, " $(inst.p) $(inst.q)")
                println(io)
            end
        end
        @info "Generated: $path"
        push!(paths, path)
    end
    paths
end

# ============================================================================
# CircuitSAT
# ============================================================================

function load_circuit_instance(config::CircuitSATConfig)
    name = basename(config.path)
    circuit = if config.format == :verilog
        CircuitIO.verilog_to_circuit(config.path)
    elseif config.format == :aag
        mktempdir() do tmpdir
            vfile = joinpath(tmpdir, "circuit.v")
            run(pipeline(`yosys -p "read_aiger $(config.path); rename -top circuit_top; write_verilog $vfile"`,
                stdout=devnull, stderr=devnull))
            circuit = CircuitIO.verilog_to_circuit(vfile)

            # Parse Verilog file to find actual output declarations
            # YOSYS uses names like "_45493_" not "po*", so we need to parse the Verilog
            verilog_content = read(vfile, String)
            output_vars = Symbol[]
            for line in split(verilog_content, "\n")
                m = match(r"^\s*output\s+(\w+);", line)
                if !isnothing(m)
                    push!(output_vars, Symbol(m.captures[1]))
                end
            end

            # Add constraint: each output must be true (for CircuitSAT miter circuits)
            for out_sym in output_vars
                push!(circuit.exprs, Assignment([out_sym], BooleanExpr(true)))
            end

            circuit
        end
    else
        error("Unsupported format: $(config.format)")
    end
    CircuitSATInstance(name, circuit, config.format, config.path)
end

function discover_circuit_files(dir::AbstractString; format::Symbol=:verilog)
    ext = format == :verilog ? ".v" : ".aag"
    filter(f -> endswith(f, ext), readdir(dir, join=true))
end

# ============================================================================
# CNF SAT
# ============================================================================

function parse_cnf_file(path::AbstractString)
    clauses = Vector{Int}[]
    num_vars, num_clauses = 0, 0

    open(path, "r") do io
        for line in eachline(io)
            line = strip(line)
            isempty(line) && continue
            startswith(line, "c") && continue

            if startswith(line, "p cnf")
                parts = split(line)
                num_vars = parse(Int, parts[3])
                num_clauses = parse(Int, parts[4])
            else
                lits = parse.(Int, filter(!isempty, split(line)))
                filter!(x -> x != 0, lits)
                !isempty(lits) && push!(clauses, lits)
            end
        end
    end

    CNFSATInstance(basename(path), num_vars, clauses, path)
end

function discover_cnf_files(dir::AbstractString)
    filter(f -> endswith(f, ".cnf"), readdir(dir, join=true))
end

function cnf_instantiation(instance::CNFSATInstance)
    clauses = [CNFClause([BoolVar(abs(lit), lit > 0) for lit in clause]) for clause in instance.clauses]
    Satisfiability(CNF(clauses); use_constraints=true)
end

# ============================================================================
# Generic read_instances dispatcher
# ============================================================================

function read_instances(::Type{FactoringProblem}, path::AbstractString)
    read_factoring_instances(path)
end

function read_instances(::Type{CircuitSATProblem}, path::AbstractString)
    if isfile(path)
        ext = lowercase(splitext(path)[2])
        format = ext == ".v" ? :verilog : :aag
        [load_circuit_instance(CircuitSATConfig(format, path))]
    else
        instances = CircuitSATInstance[]
        for f in vcat(discover_circuit_files(path; format=:verilog), discover_circuit_files(path; format=:aag))
            try
                ext = lowercase(splitext(f)[2])
                format = ext == ".v" ? :verilog : :aag
                push!(instances, load_circuit_instance(CircuitSATConfig(format, f)))
            catch e
                @warn "Failed to load: $f" exception = e
            end
        end
        instances
    end
end

function read_instances(::Type{CNFSATProblem}, path::AbstractString)
    if isfile(path)
        [parse_cnf_file(path)]
    else
        [parse_cnf_file(f) for f in discover_cnf_files(path)]
    end
end
