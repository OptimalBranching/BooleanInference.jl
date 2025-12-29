# ============================================================================
# api.jl - Unified high-level API
# ============================================================================

# ============================================================================
# Load API
# ============================================================================

"""
    load(path::String) -> AbstractInstance

Load a problem instance from file. Format auto-detected from extension.
Supported: `.v` (Verilog), `.aag` (AIGER), `.cnf` (DIMACS CNF)
"""
function load(path::AbstractString)
    isfile(path) || error("File not found: $path")
    ext = lowercase(splitext(path)[2])

    if ext == ".v"
        load_circuit_instance(CircuitSATConfig(:verilog, path))
    elseif ext in (".aag", ".aig")
        load_circuit_instance(CircuitSATConfig(:aag, path))
    elseif ext == ".cnf"
        parse_cnf_file(path)
    else
        error("Unsupported format: $ext")
    end
end

"""
    load_dir(path::String; format=:auto) -> Vector{AbstractInstance}

Load all instances from a directory.
"""
function load_dir(path::AbstractString; format::Symbol=:auto)
    isdir(path) || error("Directory not found: $path")
    instances = AbstractInstance[]

    if format in (:auto, :verilog, :aag)
        for f in vcat(discover_circuit_files(path; format=:verilog), discover_circuit_files(path; format=:aag))
            try
                push!(instances, load(f))
            catch e
                @warn "Skip: $f"
            end
        end
    end
    if format in (:auto, :cnf)
        for f in discover_cnf_files(path)
            try
                push!(instances, load(f))
            catch e
                @warn "Skip: $f"
            end
        end
    end
    instances
end

# ============================================================================
# Solve API
# ============================================================================

function _to_result(raw, solver_name::String, elapsed::Float64)
    # BooleanInference Result type (from CNFSATProblem solve)
    if hasfield(typeof(raw), :found) && hasfield(typeof(raw), :stats)
        branches = hasfield(typeof(raw.stats), :total_visited_nodes) ? raw.stats.total_visited_nodes : 0
        return SolveResult(raw.found ? SAT : UNSAT, raw.solution, elapsed, branches, solver_name)
    end

    # BooleanInferenceSolver: (is_sat::Bool, stats)
    if raw isa Tuple && length(raw) == 2 && raw[1] isa Bool
        branches = hasfield(typeof(raw[2]), :total_visited_nodes) ? raw[2].total_visited_nodes : 0
        return SolveResult(raw[1] ? SAT : UNSAT, nothing, elapsed, branches, solver_name)
    end

    # Factoring: (p, q, stats)
    if raw isa Tuple && length(raw) == 3
        p, q, stats = raw
        if !isnothing(p) && !isnothing(q)
            branches = isnothing(stats) ? 0 : (hasfield(typeof(stats), :total_visited_nodes) ? stats.total_visited_nodes : 0)
            return SolveResult(SAT, (p=p, q=q), elapsed, branches, solver_name)
        end
        return SolveResult(UNSAT, nothing, elapsed, 0, solver_name)
    end

    # CNFSolverResult
    if raw isa CNFSolverResult
        status = raw.status == :sat ? SAT : raw.status == :unsat ? UNSAT : UNKNOWN
        return SolveResult(status, raw.model, elapsed, something(raw.decisions, 0), solver_name)
    end

    SolveResult(UNKNOWN, raw, elapsed, 0, solver_name)
end

"""
    solve(instance; solver=nothing) -> SolveResult
    solve(path::String; solver=nothing) -> SolveResult

Solve a problem instance. Returns unified `SolveResult`.

# Examples
```julia
result = solve("circuit.v")
result = solve("problem.cnf", solver=Solvers.Kissat())

if result.status == SAT
    println("Solved in \$(result.time)s")
end
```
"""
function solve(path::AbstractString; solver=nothing)
    solve(load(path); solver)
end

function solve(inst::CircuitSATInstance; solver=nothing)
    s = isnothing(solver) ? default_solver(CircuitSATProblem) : solver
    elapsed = @elapsed raw = solve_instance(CircuitSATProblem, inst, s)
    _to_result(raw, solver_name(s), elapsed)
end

function solve(inst::CNFSATInstance; solver=nothing)
    s = isnothing(solver) ? default_solver(CNFSATProblem) : solver
    elapsed = @elapsed raw = solve_instance(CNFSATProblem, inst, s)
    _to_result(raw, solver_name(s), elapsed)
end

function solve(inst::FactoringInstance; solver=nothing)
    s = isnothing(solver) ? default_solver(FactoringProblem) : solver
    elapsed = @elapsed raw = solve_instance(FactoringProblem, inst, s)
    _to_result(raw, solver_name(s), elapsed)
end

"""
    factor(N; m, n, solver=nothing) -> SolveResult

Factor integer N using m-bit and n-bit factors.

# Example
```julia
result = factor(143; m=4, n=4)
if result.status == SAT
    println("143 = \$(result.solution.p) × \$(result.solution.q)")
end
```
"""
function factor(N::Integer; m::Int, n::Int, solver=nothing)
    solve(FactoringInstance(m, n, N); solver)
end

# ============================================================================
# Benchmark API
# ============================================================================

"""
    benchmark(path; solver=nothing, verbose=true) -> NamedTuple

Benchmark all instances in a file or directory.

# Returns
`(times=Float64[], branches=Int[], results=SolveResult[])`
"""
function benchmark(path::AbstractString; solver=nothing, verbose::Bool=true)
    instances = isfile(path) ? [load(path)] : load_dir(path)
    isempty(instances) && error("No instances found: $path")

    s = isnothing(solver) ? default_solver(typeof(first(instances)) <: CircuitSATInstance ? CircuitSATProblem :
                                           typeof(first(instances)) <: CNFSATInstance ? CNFSATProblem : FactoringProblem) : solver
    verbose && @info "Benchmarking $(length(instances)) instances with $(solver_name(s))"

    times, branches, results = Float64[], Int[], SolveResult[]
    for (i, inst) in enumerate(instances)
        r = solve(inst; solver=s)
        push!(times, r.time)
        push!(branches, r.branches)
        push!(results, r)
        verbose && i % 10 == 0 && @info "Progress: $i/$(length(instances))"
    end

    (times=times, branches=branches, results=results)
end
