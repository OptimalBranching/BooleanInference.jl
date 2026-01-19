# ============================================================================
# Cube-and-Conquer Interface
# ============================================================================

"""
    generate_factoring_cubes(n, m, N; cutoff, bsconfig, reducer, output_file) -> CubeResult

Generate cubes for a factoring problem using Cube-and-Conquer.

# Arguments
- `n::Int`: Bit width of first factor
- `m::Int`: Bit width of second factor
- `N::Int`: Number to factor

# Keyword Arguments
- `cutoff::AbstractCutoffStrategy`: When to emit cubes (default: RatioCutoff(0.3))
- `bsconfig::BranchingStrategy`: Branching configuration
- `reducer::AbstractReducer`: Reduction strategy (default: GammaOneReducer)
- `output_file::String`: If provided, write cubes to this file in iCNF format

# Returns
- `CubeResult`: Generated cubes and statistics

# Example
```julia
res = generate_factoring_cubes(8, 8, 143; cutoff=VarsCutoff(30))
println("Generated \$(res.n_cubes) cubes, \$(res.n_refuted) refuted")
write_cubes_icnf(res, "cubes.icnf")
```
"""
function generate_factoring_cubes(
    n::Int, m::Int, N::Int;
    cutoff::AbstractCutoffStrategy=RatioCutoff(0.3),
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=LookaheadSelector(3, 4),
        measure=NumUnfixedTensors(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=GammaOneReducer(20),
    output_file::Union{String,Nothing}=nothing
)
    # Create factoring problem
    reduction = reduceto(CircuitSAT, Factoring(n, m, N))
    circuit_sat = CircuitSAT(reduction.circuit.circuit; use_constraints=true)
    tn_problem = setup_from_sat(circuit_sat)

    @info "Cube generation" n m N nvars = length(tn_problem.doms) cutoff

    # Generate cubes
    result = generate_cubes!(tn_problem, bsconfig, reducer, cutoff)

    @info "Cube generation complete" n_cubes = result.n_cubes n_refuted = result.n_refuted

    # Write to file if requested
    if !isnothing(output_file)
        write_cubes_icnf(result, output_file)
        @info "Cubes written to $output_file"
    end

    return result
end

"""
    generate_cnf_cubes(cnf; cutoff, bsconfig, reducer, output_file) -> CubeResult

Generate cubes for a CNF problem using Cube-and-Conquer.

# Arguments
- `cnf::CNF`: CNF formula to solve

# Keyword Arguments
- `cutoff::AbstractCutoffStrategy`: When to emit cubes
- `bsconfig::BranchingStrategy`: Branching configuration
- `reducer::AbstractReducer`: Reduction strategy
- `output_file::String`: If provided, write cubes to this file in iCNF format
"""
function generate_cnf_cubes(
    cnf::ProblemReductions.CNF;
    cutoff::AbstractCutoffStrategy=RatioCutoff(0.3),
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MostOccurrenceSelector(3, 4),
        measure=NumUnfixedVars(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=GammaOneReducer(10),
    output_file::Union{String,Nothing}=nothing
)
    tn_problem = setup_from_cnf(cnf)

    # Generate cubes
    result = generate_cubes!(tn_problem, bsconfig, reducer, cutoff)

    # Write to file if requested
    if !isnothing(output_file)
        write_cubes_icnf(result, output_file)
    end

    return result
end

"""
    CubesSolveStats

Statistics from solving cubes with CDCL.
"""
struct CubesSolveStats
    cubes_solved::Int
    sat_cube_idx::Int
    total_decisions::Int
    total_conflicts::Int
    total_time::Float64
    per_cube_times::Vector{Float64}
    per_cube_decisions::Vector{Int}
    per_cube_conflicts::Vector{Int}
end

"""
    solve_cubes_with_cdcl(cubes, cnf; nvars) -> (status, solution, stats)

Solve generated cubes using CDCL solver (Kissat).

# Returns
- `status`: `:sat` if any cube is satisfiable, `:unsat` otherwise
- `solution`: The satisfying assignment (if found), or empty vector
- `stats`: CubesSolveStats with comprehensive statistics
"""
function solve_cubes_with_cdcl(cubes::Vector{Cube}, cnf::Vector{Vector{Int}}; nvars::Int)
    cubes_solved = 0
    total_decisions = 0
    total_conflicts = 0
    total_time = 0.0
    per_cube_times = Float64[]
    per_cube_decisions = Int[]
    per_cube_conflicts = Int[]

    for (idx, cube) in enumerate(cubes)
        cube.is_refuted && continue

        # Add cube literals as unit clauses
        cube_cnf = [cnf; [[lit] for lit in cube.literals]]

        cube_time = @elapsed begin
            status, model, _, cdcl_stats = solve_and_mine(cube_cnf; nvars=nvars)
        end

        cubes_solved += 1
        total_time += cube_time
        total_decisions += cdcl_stats.decisions
        total_conflicts += cdcl_stats.conflicts
        push!(per_cube_times, cube_time)
        push!(per_cube_decisions, cdcl_stats.decisions)
        push!(per_cube_conflicts, cdcl_stats.conflicts)

        if status == :sat
            stats = CubesSolveStats(cubes_solved, idx, total_decisions, total_conflicts,
                total_time, per_cube_times, per_cube_decisions, per_cube_conflicts)
            return (:sat, model, stats)
        end
    end

    stats = CubesSolveStats(cubes_solved, 0, total_decisions, total_conflicts,
        total_time, per_cube_times, per_cube_decisions, per_cube_conflicts)
    return (:unsat, Int32[], stats)
end

"""
    solve_factoring_cnc(n, m, N; cutoff, ...) -> (a, b, cnc_result::CnCResult)

Solve factoring problem using Cube-and-Conquer.

This is an end-to-end function that:
1. Generates cubes using tensor network branching
2. Solves each cube with CDCL until a solution is found

# Arguments
- `n::Int`: Bit width of first factor
- `m::Int`: Bit width of second factor
- `N::Int`: Number to factor

# Keyword Arguments
- `cutoff::AbstractCutoffStrategy`: When to emit cubes (default: RatioCutoff(0.3))
- `bsconfig::BranchingStrategy`: Branching configuration
- `reducer::AbstractReducer`: Reduction strategy

# Returns
- `(a, b, cnc_result)`: Factors and CnCResult, or `(nothing, nothing, cnc_result)` if UNSAT
"""
function solve_factoring_cnc(
    n::Int, m::Int, N::Int;
    cutoff::AbstractCutoffStrategy=ProductCutoff(10000),
    bsconfig::BranchingStrategy=BranchingStrategy(
        table_solver=TNContractionSolver(),
        selector=MostOccurrenceSelector(3, 4),
        measure=NumUnfixedTensors(),
        set_cover_solver=GreedyMerge()
    ),
    reducer::AbstractReducer=NoReducer()
    # reducer::AbstractReducer=GammaOneReducer(100)
)
    # Step 1: Setup problem
    reduction = reduceto(CircuitSAT, Factoring(n, m, N))
    circuit_sat = CircuitSAT(reduction.circuit.circuit; use_constraints=true)
    q_vars = collect(reduction.q)
    p_vars = collect(reduction.p)

    tn_problem = setup_from_sat(circuit_sat)

    # Target variables: p and q factors
    target_vars = [q_vars; p_vars]

    @info "Cube-and-Conquer setup" n m N nvars = length(tn_problem.doms) target_nvars = length(target_vars) cutoff

    # Step 2: Generate cubes
    t_cube = @elapsed cube_result = generate_cubes!(tn_problem, bsconfig, reducer, cutoff; target_vars)

    avg_lits = isempty(cube_result.cubes) ? 0.0 : sum(c -> length(c.literals), cube_result.cubes) / length(cube_result.cubes)

    @info "Cubing complete" n_cubes = cube_result.n_cubes avg_literals = round(avg_lits, digits=0) time = round(t_cube, digits=2)

    # Step 3: Convert to CNF for CDCL (only structure, no fixed vars - cube provides decisions)
    cnf = tn_to_cnf(tn_problem.static)
    nvars = num_tn_vars(tn_problem.static)

    # Step 4: Solve cubes with CDCL
    status, model, solve_stats = solve_cubes_with_cdcl(cube_result.cubes, cnf; nvars=nvars)

    # Build CnCStats
    avg_decisions = solve_stats.cubes_solved > 0 ?
                    solve_stats.total_decisions / solve_stats.cubes_solved : 0.0
    avg_conflicts = solve_stats.cubes_solved > 0 ?
                    solve_stats.total_conflicts / solve_stats.cubes_solved : 0.0
    avg_solve_time = solve_stats.cubes_solved > 0 ?
                     solve_stats.total_time / solve_stats.cubes_solved : 0.0

    cnc_stats = CnCStats(
        cube_result.n_cubes,
        cube_result.n_refuted,
        t_cube,
        avg_lits,
        solve_stats.cubes_solved,
        solve_stats.total_decisions,
        solve_stats.total_conflicts,
        avg_decisions,
        avg_conflicts,
        avg_solve_time,
        solve_stats.total_time
    )

    @info "CDCL complete" status cubes_solved = solve_stats.cubes_solved avg_decisions = round(avg_decisions, digits=1) avg_conflicts = round(avg_conflicts, digits=1) time = round(solve_stats.total_time, digits=2)

    if status != :sat
        cnc_result = CnCResult(status, Int32[], cube_result, cnc_stats)
        return (nothing, nothing, cnc_result)
    end

    # Step 5: Extract solution
    # Model from CDCL uses signed literals: positive = true, negative = false
    a = 0
    b = 0
    for (i, var_idx) in enumerate(q_vars)
        if var_idx <= length(model) && model[var_idx] > 0
            a |= (1 << (i - 1))
        end
    end
    for (i, var_idx) in enumerate(p_vars)
        if var_idx <= length(model) && model[var_idx] > 0
            b |= (1 << (i - 1))
        end
    end

    cnc_result = CnCResult(status, model, cube_result, cnc_stats)
    return (a, b, cnc_result)
end
