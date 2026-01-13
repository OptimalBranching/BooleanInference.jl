# CDCL-guided search: CDCL does low-level solving, OB-SAT provides guidance

abstract type CubeStrategy end
struct RegionBasedCubes <: CubeStrategy end
struct ConnectivityCubes <: CubeStrategy end

struct CDCLGuidedResult
    status::Symbol
    model::Union{Vector{Int32}, Nothing}
    solution::Vector{DomainMask}
    stats::BranchingStats
    adaptive_state::AdaptiveState
    cdcl_calls::Int
    total_conflicts::Int
    learned_clauses::Vector{Vector{Int}}
    learned_lbds::Vector{Int}
end

function solve_with_cdcl_guidance(
    problem::TNProblem,
    config::BranchingStrategy,
    cube_strategy::CubeStrategy=RegionBasedCubes();
    max_iterations::Int=100,
    max_cube_size::Int=10,
    adaptive_alpha::Float64=0.1,
    conflict_limit::Int=0,
    max_learned_len::Int=10,
    max_learned_lbd::Int=5,
    verbose::Bool=false
)
    nvars = length(problem.static.vars)
    adaptive_state = AdaptiveState(nvars; alpha=adaptive_alpha, enabled=true)

    empty!(problem.buffer.branching_cache)
    region_cache = init_cache(problem, config.table_solver, config.measure, config.set_cover_solver, config.selector)

    cnf, cnf_nvars = tn_to_cnf_with_doms(problem.static, problem.doms)
    verbose && println("Problem: $cnf_nvars variables, $(length(cnf)) clauses")

    cdcl_calls = 0
    total_conflicts = 0
    all_learned_clauses = Vector{Vector{Int}}()
    all_learned_lbds = Vector{Int}()
    accumulated_learned = Vector{Vector{Int}}()  # High-quality clauses to add to CNF

    for iter in 1:max_iterations
        # Inherit: Add accumulated learned clauses to CNF for this iteration
        if !isempty(accumulated_learned)
            current_cnf = vcat(cnf, accumulated_learned)
            verbose && println("\nIteration $iter: CNF strengthened with $(length(accumulated_learned)) learned clauses ($(length(current_cnf)) total)")
        else
            current_cnf = cnf
            verbose && println("\nIteration $iter: Using original CNF ($(length(cnf)) clauses)")
        end

        cube = generate_cube_with_structure(cube_strategy, problem, config, region_cache, max_cube_size, adaptive_state)
        verbose && println("  Cube size: $(length(cube))")
        verbose && println("  Cube: ", cube)

        feedback = solve_with_assumptions(current_cnf, cube; conflict_limit=conflict_limit, max_learned_len=max_learned_len, max_learned_lbd=max_learned_lbd)
        @show feedback.unsat_core
        @show feedback.learned_clauses
        cdcl_calls += 1
        total_conflicts += feedback.conflicts

        # Collect all learned clauses for statistics
        append!(all_learned_clauses, feedback.learned_clauses)
        append!(all_learned_lbds, feedback.learned_lbds)

        # Filter high-quality clauses to inherit in next iteration
        if feedback.status != :sat
            for (clause, lbd) in zip(feedback.learned_clauses, feedback.learned_lbds)
                # Only inherit short clauses with low LBD (high quality)
                if 2 <= length(clause) <= 3 && lbd <= 3
                    push!(accumulated_learned, clause)
                end
            end
            if !isempty(feedback.learned_clauses)
                new_quality = count(2 <= length(c) <= 3 && l <= 3 for (c, l) in zip(feedback.learned_clauses, feedback.learned_lbds))
                verbose && println("  CDCL result: $(feedback.status), $(feedback.conflicts) conflicts, $new_quality high-quality clauses added")
            else
                verbose && println("  CDCL result: $(feedback.status), $(feedback.conflicts) conflicts")
            end
        else
            verbose && println("  CDCL result: $(feedback.status), $(feedback.conflicts) conflicts")
        end

        if feedback.status == :sat
            verbose && println("\n✓ SAT found!")
            solution = model_to_domains(feedback.model, problem.doms)
            return CDCLGuidedResult(
                :sat, feedback.model, solution,
                problem.stats, adaptive_state,
                cdcl_calls, total_conflicts,
                all_learned_clauses, all_learned_lbds
            )
        elseif feedback.status == :unsat
            assigned_vars = abs.(cube)
            update_from_cdcl_feedback!(adaptive_state, assigned_vars, feedback)
            verbose && !isempty(feedback.unsat_core) && println("  UNSAT core size: $(length(feedback.unsat_core))")
        else
            verbose && println("  CDCL returned unknown")
        end
    end

    verbose && println("\n✗ Max iterations reached without solution")
    return CDCLGuidedResult(
        :unknown, nothing, DomainMask[],
        problem.stats, adaptive_state,
        cdcl_calls, total_conflicts,
        all_learned_clauses, all_learned_lbds
    )
end

# Use OB-SAT region selection - build cube iteratively by making multiple decisions
function generate_cube_with_structure(
    ::RegionBasedCubes,
    problem::TNProblem,
    config::BranchingStrategy,
    region_cache::RegionCache,
    max_size::Int,
    adaptive_state::AdaptiveState
)
    cube = Int[]
    isempty(get_unfixed_vars(problem)) && return cube

    # Simulate bbsat! for a few steps, accumulating decisions into cube
    current_doms = copy(problem.doms)

    while length(cube) < max_size
        # Create temporary problem with current domains
        temp_problem = TNProblem(problem.static, current_doms, problem.stats, problem.buffer)
        isempty(get_unfixed_vars(temp_problem)) && break

        # Get next branching decision from OB-SAT
        clauses, variables = findbest(region_cache, temp_problem, config.measure, config.set_cover_solver, config.selector, 0)
        isnothing(clauses) && break

        # Select best clause based on learned difficulties
        clause = select_best_clause(clauses, variables, adaptive_state)
        @show clause

        # Extract branching literals from this clause
        new_lits = Int[]
        for (i, var_id) in enumerate(variables)
            bit = UInt64(1) << (i - 1)
            if (clause.mask & bit) != 0
                value = (clause.val & bit) != 0 ? 1 : -1
                push!(new_lits, value * var_id)
            end
        end

        isempty(new_lits) && break

        # Add to cube
        append!(cube, new_lits)
        length(cube) >= max_size && break

        # Apply decision and propagate for next iteration
        new_doms = probe_branch!(temp_problem, problem.buffer, current_doms, clause, variables)
        has_contradiction(new_doms) && break
        current_doms = copy(new_doms)
    end

    # Trim to max_size
    return cube[1:min(length(cube), max_size)]
end

# Select clause with lowest total difficulty score, randomize ties
function select_best_clause(clauses, variables, adaptive_state::AdaptiveState)
    length(clauses) == 1 && return clauses[1]

    # Score each clause by sum of difficulties
    clause_scores = Tuple{Float64, Int}[]
    for (idx, clause) in enumerate(clauses)
        score = 0.0
        for (i, var_id) in enumerate(variables)
            bit = UInt64(1) << (i - 1)
            if (clause.mask & bit) != 0 && var_id <= length(adaptive_state.var_difficulty)
                score += adaptive_state.var_difficulty[var_id]
            end
        end
        push!(clause_scores, (score, idx))
    end

    # Sort by score, pick randomly among best
    sort!(clause_scores, by=x->x[1])
    best_score = clause_scores[1][1]

    # Get all clauses with best score (handle ties)
    best_indices = [idx for (score, idx) in clause_scores if score ≈ best_score]

    # Randomize among ties
    selected_idx = rand(best_indices)
    return clauses[selected_idx]
end

# Fallback: use connectivity scoring
function generate_cube_with_structure(
    ::ConnectivityCubes,
    problem::TNProblem,
    config::BranchingStrategy,
    region_cache::RegionCache,
    max_size::Int,
    adaptive_state::AdaptiveState
)
    cube = Int[]
    unfixed_vars = get_unfixed_vars(problem)
    isempty(unfixed_vars) && return cube

    scores = compute_var_cover_scores_weighted(problem)
    var_scores = [(v, scores[v]) for v in unfixed_vars if scores[v] > 0]
    sort!(var_scores, by=x->x[2], rev=true)

    cube_size = min(max_size, length(var_scores))
    for i in 1:cube_size
        var = var_scores[i][1]
        value = has1(problem.doms[var]) ? 1 : -1
        push!(cube, value * var)
    end

    return cube
end

function model_to_domains(model::Vector{Int32}, initial_doms::Vector{DomainMask})
    solution = copy(initial_doms)
    for lit in model
        var = abs(lit)
        var <= length(solution) || continue
        solution[var] = lit > 0 ? DomainMask(0b10) : DomainMask(0b01)
    end
    return solution
end

function solve_factoring_with_cdcl_guidance(
    m::Int, n::Int, N::Integer,
    cube_strategy::CubeStrategy=RegionBasedCubes();
    max_iterations::Int=100,
    max_cube_size::Int=10,
    adaptive_alpha::Float64=0.1,
    conflict_limit::Int=0,
    max_learned_len::Int=10,
    max_learned_lbd::Int=5,
    verbose::Bool=false
)
    fproblem = Factoring(m, n, N)
    circuit_sat = reduceto(CircuitSAT, fproblem)
    circuit_problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true)
    tn_problem = setup_from_sat(circuit_problem)

    config = BranchingStrategy(
        table_solver = TNContractionSolver(),
        selector = MostOccurrenceSelector(3, 4),
        measure = NumUnfixedTensors(),
        set_cover_solver = GreedyMerge()
    )

    result = solve_with_cdcl_guidance(
        tn_problem, config, cube_strategy;
        max_iterations=max_iterations,
        max_cube_size=max_cube_size,
        adaptive_alpha=adaptive_alpha,
        conflict_limit=conflict_limit,
        max_learned_len=max_learned_len,
        max_learned_lbd=max_learned_lbd,
        verbose=verbose
    )

    return result
end
