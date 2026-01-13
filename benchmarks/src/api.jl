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

function _extract_bi_stats(stats)
    # branches_explored = total branches actually explored (for comparison with CDCL decisions)
    branches = hasfield(typeof(stats), :branches_explored) ? stats.branches_explored : 0
    gamma_one = hasfield(typeof(stats), :gamma_one_count) ? stats.gamma_one_count : 0
    # avg_vars_per_branch is a computed property, not a field - use try/catch
    avg_vars = try
        Float64(stats.avg_vars_per_branch)
    catch
        0.0
    end
    # Total vars fixed by γ=1 and γ>1 branches
    gamma_one_vars = hasfield(typeof(stats), :vars_by_gamma_one) ? stats.vars_by_gamma_one : 0
    branch_vars = hasfield(typeof(stats), :vars_by_branches) ? stats.vars_by_branches : 0
    return (branches, gamma_one, avg_vars, gamma_one_vars, branch_vars)
end

function _to_result(raw, solver_name::String, elapsed::Float64)
    # BooleanInference Result type (from CNFSATProblem solve)
    if hasfield(typeof(raw), :found) && hasfield(typeof(raw), :stats)
        branches, gamma_one, avg_vars, γ1_vars, br_vars = _extract_bi_stats(raw.stats)
        return SolveResult(raw.found ? SAT : UNSAT, raw.solution, elapsed, branches, gamma_one, avg_vars, γ1_vars, br_vars, solver_name)
    end

    # BooleanInferenceSolver: (is_sat::Bool, stats)
    if raw isa Tuple && length(raw) == 2 && raw[1] isa Bool
        branches, gamma_one, avg_vars, γ1_vars, br_vars = _extract_bi_stats(raw[2])
        return SolveResult(raw[1] ? SAT : UNSAT, nothing, elapsed, branches, gamma_one, avg_vars, γ1_vars, br_vars, solver_name)
    end

    # Factoring: (p, q, stats)
    if raw isa Tuple && length(raw) == 3
        p, q, stats = raw
        if !isnothing(p) && !isnothing(q)
            branches, gamma_one, avg_vars, γ1_vars, br_vars = isnothing(stats) ? (0, 0, 0.0, 0, 0) : _extract_bi_stats(stats)
            return SolveResult(SAT, (p=p, q=q), elapsed, branches, gamma_one, avg_vars, γ1_vars, br_vars, solver_name)
        end
        return SolveResult(UNSAT, nothing, elapsed, 0, 0, 0.0, 0, 0, solver_name)
    end

    # CNFSolverResult (CDCL solvers - no γ=1 tracking)
    if raw isa CNFSolverResult
        status = raw.status == :sat ? SAT : raw.status == :unsat ? UNSAT : UNKNOWN
        return SolveResult(status, raw.model, elapsed, something(raw.decisions, 0), 0, 0.0, 0, 0, solver_name)
    end

    SolveResult(UNKNOWN, raw, elapsed, 0, 0, 0.0, 0, 0, solver_name)
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
    return solve(FactoringInstance(m, n, N); solver)
end

"""
    factor_batch(Ns; m, n, solver=nothing, verbose=true) -> Vector{SolveResult}

Factor multiple integers efficiently using a shared benchmark.

When `solver` is not provided, automatically creates a `FactoringBenchmarkSolver`
that pre-computes clustering and N-independent contractions once, then reuses
them for all instances. This is significantly faster than calling `factor()`
repeatedly for many instances.

# Arguments
- `Ns`: Collection of integers to factor
- `m::Int`: Number of bits for first factor
- `n::Int`: Number of bits for second factor

# Keyword Arguments
- `solver`: Optional solver (default: auto-created BIBenchmark)
- `verbose::Bool`: Print progress (default: true)

# Returns
Vector of `SolveResult` in same order as input `Ns`

# Example
```julia
# Factor 100 random semiprimes efficiently
Ns = [rand(2^15:2^16-1) for _ in 1:100]
results = factor_batch(Ns; m=8, n=8)

# Check success rate
sat_count = count(r -> r.status == SAT, results)
println("Solved: \$sat_count / \$(length(Ns))")
```
"""
function factor_batch(Ns; m::Int, n::Int, solver=nothing, verbose::Bool=true)
    isempty(Ns) && return SolveResult[]

    # Auto-create benchmark solver if not provided
    s = if isnothing(solver)
        verbose && @info "Creating FactoringBenchmark for $(m)×$(n) bit factoring..."
        Solvers.BIBenchmark(m, n)
    else
        solver
    end

    verbose && @info "Solving $(length(Ns)) factoring instances with $(solver_name(s))"

    results = SolveResult[]
    for (i, N) in enumerate(Ns)
        inst = FactoringInstance(m, n, N)
        elapsed = @elapsed raw = solve_instance(FactoringProblem, inst, s)
        push!(results, _to_result(raw, solver_name(s), elapsed))
        verbose && i % 10 == 0 && @info "Progress: $i/$(length(Ns))"
    end

    results
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
