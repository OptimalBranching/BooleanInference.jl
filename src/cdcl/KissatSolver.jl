# KissatSolver.jl - Kissat SAT solver backend via command line
# Uses homebrew-installed kissat at /opt/homebrew/bin/kissat

const KISSAT_PATH = "/opt/homebrew/bin/kissat"

"""
    write_cnf_file(path::String, cnf::Vector{Vector{Int}}, nvars::Int)

Write CNF to DIMACS format file.
"""
function write_cnf_file(path::String, cnf::Vector{<:AbstractVector{<:Integer}}, nvars::Int)
    open(path, "w") do io
        println(io, "p cnf $nvars $(length(cnf))")
        for clause in cnf
            for lit in clause
                print(io, lit, " ")
            end
            println(io, "0")
        end
    end
end

"""
    CDCLStats

Statistics from CDCL solver execution.
"""
struct CDCLStats
    decisions::Int
    conflicts::Int
    propagations::Int
end

CDCLStats() = CDCLStats(0, 0, 0)

function Base.show(io::IO, s::CDCLStats)
    print(io, "CDCLStats(decisions=$(s.decisions), conflicts=$(s.conflicts))")
end

"""
    parse_kissat_output(output::String, nvars::Int) -> (status::Symbol, model::Vector{Int32}, stats::CDCLStats)

Parse kissat output to extract status, model, and statistics.
Returns (:sat/:unsat/:unknown, model, stats) where model[i] = ±i or 0.
"""
function parse_kissat_output(output::String, nvars::Int)
    status = :unknown
    model = zeros(Int32, nvars)
    decisions = 0
    conflicts = 0
    propagations = 0

    for line in split(output, '\n')
        line = strip(line)

        # Check status line (check UNSATISFIABLE first since it contains SATISFIABLE)
        if startswith(line, "s ")
            if occursin("UNSATISFIABLE", line)
                status = :unsat
            elseif occursin("SATISFIABLE", line)
                status = :sat
            end
        end

        # Parse model (v lines)
        if startswith(line, "v ")
            parts = split(line)[2:end]  # Skip "v"
            for part in parts
                lit = tryparse(Int32, part)
                isnothing(lit) && continue
                lit == 0 && break
                var = abs(lit)
                if var <= nvars
                    model[var] = lit
                end
            end
        end

        # Parse statistics (c lines)
        if startswith(line, "c ")
            # c decisions:                          417082
            m = match(r"c\s+decisions:\s+(\d+)", line)
            if !isnothing(m)
                decisions = parse(Int, m.captures[1])
            end
            # c conflicts:                          216272
            m = match(r"c\s+conflicts:\s+(\d+)", line)
            if !isnothing(m)
                conflicts = parse(Int, m.captures[1])
            end
            # c propagations:                       12345678
            m = match(r"c\s+propagations:\s+(\d+)", line)
            if !isnothing(m)
                propagations = parse(Int, m.captures[1])
            end
        end
    end

    return status, model, CDCLStats(decisions, conflicts, propagations)
end

"""
    solve_cnf(cnf; nvars=nothing, timeout=0) -> (status::Symbol, model::Vector{Int32}, stats::CDCLStats)

Solve CNF using Kissat.

Arguments:
- `cnf`: Vector of clauses, each clause is a vector of literals
- `nvars`: Number of variables (auto-inferred if not provided)
- `timeout`: Timeout in seconds (0 = no timeout)

Returns:
- `status`: `:sat`, `:unsat`, or `:unknown`
- `model`: Assignment vector where model[i] = ±i (sign indicates true/false), or 0 if unknown
- `stats`: CDCLStats with decisions, conflicts, propagations
"""
function solve_cnf(cnf::Vector{<:AbstractVector{<:Integer}};
    nvars::Union{Int,Nothing}=nothing,
    timeout::Int=0)

    # Infer nvars if not provided
    if isnothing(nvars)
        nvars = 0
        for clause in cnf
            for lit in clause
                nvars = max(nvars, abs(Int(lit)))
            end
        end
    end

    # Handle empty CNF
    if isempty(cnf)
        return :sat, zeros(Int32, nvars), CDCLStats()
    end

    # Write CNF to temp file, run kissat, parse output
    mktempdir() do dir
        cnf_path = joinpath(dir, "problem.cnf")
        write_cnf_file(cnf_path, cnf, nvars)

        # Build command - kissat returns exit code 10 (SAT), 20 (UNSAT), 0 (unknown/interrupted)
        # Use ignorestatus to avoid exception on non-zero exit
        cmd = if timeout > 0
            `/opt/homebrew/bin/gtimeout $(timeout)s $KISSAT_PATH $cnf_path`
        else
            `$KISSAT_PATH $cnf_path`
        end

        # Run kissat with ignorestatus to handle exit codes 10/20
        output = read(ignorestatus(cmd), String)

        return parse_kissat_output(output, nvars)
    end
end

"""
    solve_and_mine(cnf; nvars=nothing, conflict_limit=0, max_len=3, max_lbd=0)
        -> (status::Symbol, model::Vector{Int32}, learned::Vector{Vector{Int32}}, stats::CDCLStats)

API-compatible wrapper for Kissat. Note: Kissat doesn't expose learned clauses,
so `learned` is always empty. The `conflict_limit`, `max_len`, `max_lbd` parameters
are ignored (kept for API compatibility with CaDiCaL interface).

Returns stats with decisions, conflicts, and propagations.
"""
function solve_and_mine(cnf::Vector{<:AbstractVector{<:Integer}};
    nvars::Union{Int,Nothing}=nothing,
    conflict_limit::Integer=0,
    max_len::Integer=3,
    max_lbd::Integer=0)

    # Infer nvars if not provided
    if isnothing(nvars)
        nvars = 0
        for clause in cnf
            for lit in clause
                nvars = max(nvars, abs(Int(lit)))
            end
        end
    end

    status, model, stats = solve_cnf(cnf; nvars=nvars)

    # Kissat doesn't expose learned clauses via CLI
    learned = Vector{Vector{Int32}}()

    return status, model, learned, stats
end
