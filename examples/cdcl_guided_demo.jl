using BooleanInference
using ProblemReductions: Factoring, reduceto, CircuitSAT
using OptimalBranchingCore: GreedyMerge
using Statistics: mean

println("=" ^ 70)
println("CDCL-Guided Search Demo")
println("=" ^ 70)

# Setup factoring problem
N = 32031010069
println("\nProblem: Factor N = $N")
println("Bit size: ", ceil(Int, log2(N)))

fproblem = Factoring(18, 18, N)
circuit_sat = reduceto(CircuitSAT, fproblem);
circuit_problem = CircuitSAT(circuit_sat.circuit.circuit; use_constraints=true);
tn_problem = setup_from_sat(circuit_problem)

println("\nTensor Network:")
println("  Variables: ", length(tn_problem.static.vars))
println("  Tensors: ", length(tn_problem.static.tensors))

# Configure branching strategy
config = BranchingStrategy(
    table_solver = TNContractionSolver(),
    selector = LookaheadSelector(3, 4),
    measure = NumUnfixedTensors(),
    set_cover_solver = GreedyMerge()
)

result = solve_with_cdcl_guidance(
    tn_problem,
    config,
    RegionBasedCubes();
    max_iterations=100,
    max_cube_size=5,
    adaptive_alpha=0.15,
    max_learned_len=10,
    max_learned_lbd=5,
    verbose=true
)

println("\n" * "=" ^ 70)
println("Results")
println("=" ^ 70)

println("\nStatus: ", result.status)
println("CDCL calls: ", result.cdcl_calls)
println("Total conflicts: ", result.total_conflicts)

if result.cdcl_calls > 0
    println("Avg conflicts/call: ",
            round(result.total_conflicts / result.cdcl_calls, digits=2))
end

if result.status == :sat
    println("\n✓ Solution found!")
    println("Variables fixed: ", count(is_fixed, result.solution))
else
    println("\n✗ No solution found within iteration limit")
end

# Analyze learned clauses
if !isempty(result.learned_clauses)
    nvars = length(tn_problem.static.vars)
    stats = analyze_learned_clauses(result.learned_clauses, result.learned_lbds, nvars; min_overlap_count=3)
    print_learned_stats(stats; top_k=15)

    # Count clauses suitable for tensor conversion
    println("\n" * "=" ^ 70)
    println("Clauses Suitable for Tensor Conversion")
    println("=" ^ 70)

    tensor_candidates = []
    for (clause, lbd) in zip(result.learned_clauses, result.learned_lbds)
        if 2 <= length(clause) <= 3 && lbd <= 3
            push!(tensor_candidates, (clause, lbd))
        end
    end

    println("Total clauses with 2 <= length <= 3 AND lbd <= 3: ", length(tensor_candidates))

    # Breakdown by length and LBD
    for len in 2:3
        for lbd_val in 1:3
            count = sum(length(c) == len && l == lbd_val for (c, l) in tensor_candidates)
            count > 0 && println("  Length $len, LBD $lbd_val: $count clauses")
        end
    end

    if !isempty(tensor_candidates)
        println("\nExample clauses (first 10):")
        for i in 1:min(10, length(tensor_candidates))
            clause, lbd = tensor_candidates[i]
            println("  $clause (LBD: $lbd)")
        end
    end

    # Find variable clusters
    clusters = find_variable_clusters(stats; min_cluster_size=3, min_overlap_threshold=5)
    print_variable_clusters(clusters; max_display=5)

    # Extract implications from binary clauses
    implications = extract_implications(result.learned_clauses)
    if !isempty(implications)
        println("\n" * "=" ^ 70)
        println("Binary Implications (from learned binary clauses)")
        println("=" ^ 70)
        println("Total implications: ", length(implications))
        println("\nExample implications (first 10):")
        for i in 1:min(10, length(implications))
            (ant, cons) = implications[i]
            ant_str = ant > 0 ? "x$(abs(ant))" : "¬x$(abs(ant))"
            cons_str = cons > 0 ? "x$(abs(cons))" : "¬x$(abs(cons))"
            println("  $ant_str → $cons_str")
        end
    end

    # Analyze learned clause variables in tensor network
    mapping = analyze_learned_in_tensor_network(
        result.learned_clauses, result.learned_lbds, tn_problem;
        top_k=50
    )
    print_tensor_network_analysis(mapping, stats; top_k=20)

    # Analyze tensor connectivity
    tensor_overlaps = analyze_tensor_connectivity(mapping, tn_problem; min_overlap=2)

    # Check clause novelty
    novelty = analyze_clause_novelty(result.learned_clauses, result.learned_lbds, tn_problem)

    # Check if different clauses share the same variable sets
    println("\n" * "=" ^ 70)
    println("Variable Set Overlap Analysis")
    println("=" ^ 70)

    # Group clauses by their variable sets (ignoring polarity)
    var_set_to_clauses = Dict{Set{Int}, Vector{Vector{Int}}}()

    for clause in result.learned_clauses
        var_set = Set(abs.(clause))
        if !haskey(var_set_to_clauses, var_set)
            var_set_to_clauses[var_set] = []
        end
        push!(var_set_to_clauses[var_set], clause)
    end

    # Count how many variable sets have multiple clauses
    duplicate_var_sets = filter(p -> length(p.second) > 1, var_set_to_clauses)

    println("Total learned clauses: ", length(result.learned_clauses))
    println("Unique variable sets: ", length(var_set_to_clauses))
    println("Variable sets with multiple clauses: ", length(duplicate_var_sets))

    if !isempty(duplicate_var_sets)
        println("\n⚠ Multiple clauses share the same variable sets!")
        println("  → These clauses constrain the same variables differently\n")

        # Analyze clause lengths for duplicate variable sets
        println("Clause Length Distribution for Duplicate Variable Sets:")
        println("-" ^ 60)

        length_stats = Dict{Int, Int}()  # varset_size -> count of duplicate sets
        clauses_per_length = Dict{Int, Vector{Int}}()  # varset_size -> [num_clauses_per_set]

        for (var_set, clauses) in duplicate_var_sets
            varset_size = length(var_set)
            length_stats[varset_size] = get(length_stats, varset_size, 0) + 1

            if !haskey(clauses_per_length, varset_size)
                clauses_per_length[varset_size] = []
            end
            push!(clauses_per_length[varset_size], length(clauses))
        end

        for varset_size in sort(collect(keys(length_stats)))
            count = length_stats[varset_size]
            clause_counts = clauses_per_length[varset_size]
            avg_clauses = round(mean(clause_counts), digits=1)
            max_clauses = maximum(clause_counts)
            total_clauses = sum(clause_counts)

            println("  Variable set size $varset_size: $count sets, avg $(avg_clauses) clauses/set, max $max_clauses, total $total_clauses clauses")
        end

        # Sort by number of clauses per variable set
        sorted_dups = sort(collect(duplicate_var_sets), by=p->length(p.second), rev=true)

        println("\nTop 10 variable sets with most clauses:")
        for i in 1:min(10, length(sorted_dups))
            (var_set, clauses) = sorted_dups[i]
            varset_size = length(var_set)
            println("\nVariable set {", join(["x$v" for v in sort(collect(var_set))], ", "), "} (size: $varset_size)")
            println("  Number of clauses: ", length(clauses))
            println("  Clauses:")
            for clause in clauses[1:min(5, length(clauses))]
                println("    $clause (length: $(length(clause)))")
            end
            length(clauses) > 5 && println("    ... and $(length(clauses) - 5) more")
        end

        # Show statistics on configs covered
        println("\n" * "=" ^ 70)
        println("Configuration Coverage Analysis")
        println("=" ^ 70)

        println("\nFor duplicate variable sets, how many configs are violated?")
        for varset_size in sort(collect(keys(length_stats)))
            total_configs = 2^varset_size
            sample_sets = filter(p -> length(first(p)) == varset_size, collect(duplicate_var_sets))

            if !isempty(sample_sets)
                # Sample a few to show coverage
                println("\nVariable set size $varset_size (2^$varset_size = $total_configs total configs):")

                for (var_set, clauses) in sample_sets[1:min(3, length(sample_sets))]
                    num_violated = length(clauses)
                    coverage_pct = round(100 * num_violated / total_configs, digits=1)
                    println("  $(length(clauses)) clauses = $num_violated/$total_configs configs violated ($coverage_pct%)")
                end
            end
        end
    else
        println("\n✓ Each variable set appears in exactly one clause")
        println("  → No overlap, all clauses are independent")
    end
end

println("\n" * "=" ^ 70)
println("Learned Difficulties (Top 10)")
println("=" ^ 70)

difficulties = result.adaptive_state.var_difficulty
sorted_idx = sortperm(difficulties, rev=true)

for i in 1:min(10, length(sorted_idx))
    var = sorted_idx[i]
    println("  x$var: ", round(difficulties[var], digits=2))
end

println("\nEdge hardness entries: ", length(result.adaptive_state.edge_hardness))
