# Statistical analysis of CDCL learned clauses

struct LearnedClauseStats
    total_clauses::Int
    length_distribution::Dict{Int, Int}

    # Unit clauses (length 1) - directly applicable
    unit_clauses::Vector{Int}

    # Variable frequency in learned clauses
    var_frequency::Vector{Int}
    positive_freq::Vector{Int}
    negative_freq::Vector{Int}

    # Clause overlap analysis
    pairwise_overlap::Dict{Tuple{Int,Int}, Int}  # How many clauses contain both vars
    high_overlap_pairs::Vector{Tuple{Int,Int,Int}}  # (var1, var2, count)

    # Clause clustering by shared variables
    clause_groups::Vector{Vector{Int}}  # Groups of clause indices with high overlap
end

function analyze_learned_clauses(
    learned_clauses::Vector{Vector{Int}},
    learned_lbds::Vector{Int},
    nvars::Int;
    min_overlap_count::Int=3
)
    n_clauses = length(learned_clauses)

    # Length distribution
    length_dist = Dict{Int, Int}()
    for clause in learned_clauses
        len = length(clause)
        length_dist[len] = get(length_dist, len, 0) + 1
    end

    # Extract unit clauses
    unit_clauses = Int[]
    for clause in learned_clauses
        length(clause) == 1 && push!(unit_clauses, clause[1])
    end

    # Variable frequency analysis
    var_freq = zeros(Int, nvars)
    pos_freq = zeros(Int, nvars)
    neg_freq = zeros(Int, nvars)

    for clause in learned_clauses
        for lit in clause
            var = abs(lit)
            var > nvars && continue
            var_freq[var] += 1
            if lit > 0
                pos_freq[var] += 1
            else
                neg_freq[var] += 1
            end
        end
    end

    # Pairwise overlap analysis
    overlap = Dict{Tuple{Int,Int}, Int}()
    for clause in learned_clauses
        vars = unique(abs.(clause))
        for i in 1:length(vars)
            for j in (i+1):length(vars)
                v1, v2 = minmax(vars[i], vars[j])
                overlap[(v1, v2)] = get(overlap, (v1, v2), 0) + 1
            end
        end
    end

    # Find high overlap pairs
    high_overlap = Tuple{Int,Int,Int}[]
    for ((v1, v2), count) in overlap
        count >= min_overlap_count && push!(high_overlap, (v1, v2, count))
    end
    sort!(high_overlap, by=x->x[3], rev=true)

    # Clause clustering (simplified: group by most frequent variable)
    clause_groups = Vector{Int}[]
    # TODO: implement more sophisticated clustering if needed

    return LearnedClauseStats(
        n_clauses, length_dist,
        unit_clauses,
        var_freq, pos_freq, neg_freq,
        overlap, high_overlap,
        clause_groups
    )
end

function print_learned_stats(stats::LearnedClauseStats; top_k::Int=20)
    println("=" ^ 70)
    println("Learned Clause Analysis")
    println("=" ^ 70)

    println("\nTotal clauses: ", stats.total_clauses)

    # Length distribution
    println("\nLength distribution:")
    for len in sort(collect(keys(stats.length_distribution)))
        count = stats.length_distribution[len]
        pct = round(100 * count / stats.total_clauses, digits=1)
        println("  Length $len: $count clauses ($pct%)")
    end

    # Unit clauses
    println("\n" * "=" ^ 70)
    println("Unit Clauses (directly applicable)")
    println("=" ^ 70)
    println("Count: ", length(stats.unit_clauses))
    if !isempty(stats.unit_clauses)
        println("\nLiterals:")
        for lit in stats.unit_clauses[1:min(20, length(stats.unit_clauses))]
            var = abs(lit)
            sign = lit > 0 ? "+" : "-"
            println("  x$var = $(sign == "+" ? "true" : "false")  (literal: $sign$var)")
        end
        length(stats.unit_clauses) > 20 && println("  ... and $(length(stats.unit_clauses) - 20) more")
    end

    # Variable frequency
    println("\n" * "=" ^ 70)
    println("Most Frequent Variables in Learned Clauses (Top $top_k)")
    println("=" ^ 70)

    var_indices = sortperm(stats.var_frequency, rev=true)
    println("\nVar ID | Total | Positive | Negative | Polarity Bias")
    println("-" ^ 60)
    for i in 1:min(top_k, length(var_indices))
        var = var_indices[i]
        total = stats.var_frequency[var]
        total == 0 && break
        pos = stats.positive_freq[var]
        neg = stats.negative_freq[var]
        bias = pos - neg
        bias_str = bias > 0 ? "+$bias" : "$bias"
        println("  x$var: $total occurrences ($pos pos, $neg neg, bias: $bias_str)")
    end

    # High overlap pairs
    println("\n" * "=" ^ 70)
    println("High Overlap Variable Pairs (Top $top_k)")
    println("=" ^ 70)
    println("Variables that frequently appear together in learned clauses")
    println("\nVar1 | Var2 | Co-occurrence Count")
    println("-" ^ 50)
    for i in 1:min(top_k, length(stats.high_overlap_pairs))
        (v1, v2, count) = stats.high_overlap_pairs[i]
        println("  x$v1 ↔ x$v2: $count clauses")
    end

    if length(stats.high_overlap_pairs) > top_k
        println("  ... and $(length(stats.high_overlap_pairs) - top_k) more pairs")
    end
end

# Extract implications from binary clauses
function extract_implications(learned_clauses::Vector{Vector{Int}})
    implications = Tuple{Int, Int}[]  # (antecedent, consequent)

    for clause in learned_clauses
        length(clause) == 2 || continue
        # Binary clause [a, b] means (¬a ∨ b), which is (a → b) and (¬b → ¬a)
        lit1, lit2 = clause[1], clause[2]
        push!(implications, (-lit1, lit2))   # ¬a → b
        push!(implications, (-lit2, lit1))   # ¬b → a
    end

    return implications
end

# Identify variable clusters based on co-occurrence
function find_variable_clusters(
    stats::LearnedClauseStats;
    min_cluster_size::Int=3,
    min_overlap_threshold::Int=5
)
    # Build adjacency based on high overlap
    adjacency = Dict{Int, Set{Int}}()

    for (v1, v2, count) in stats.high_overlap_pairs
        count < min_overlap_threshold && continue

        if !haskey(adjacency, v1)
            adjacency[v1] = Set{Int}()
        end
        if !haskey(adjacency, v2)
            adjacency[v2] = Set{Int}()
        end
        push!(adjacency[v1], v2)
        push!(adjacency[v2], v1)
    end

    # Find connected components (simple greedy clustering)
    visited = Set{Int}()
    clusters = Vector{Int}[]

    for var in keys(adjacency)
        var in visited && continue

        # BFS to find cluster
        cluster = Int[var]
        queue = [var]
        push!(visited, var)

        while !isempty(queue)
            current = popfirst!(queue)
            neighbors = get(adjacency, current, Set{Int}())

            for neighbor in neighbors
                neighbor in visited && continue
                push!(cluster, neighbor)
                push!(queue, neighbor)
                push!(visited, neighbor)
            end
        end

        length(cluster) >= min_cluster_size && push!(clusters, sort(cluster))
    end

    sort!(clusters, by=length, rev=true)
    return clusters
end

function print_variable_clusters(clusters::Vector{Vector{Int}}; max_display::Int=10)
    println("\n" * "=" ^ 70)
    println("Variable Clusters (frequently co-occurring)")
    println("=" ^ 70)
    println("These variables tend to appear together in conflicts\n")

    for (i, cluster) in enumerate(clusters[1:min(max_display, length(clusters))])
        println("Cluster $i ($(length(cluster)) variables):")
        if length(cluster) <= 15
            println("  ", join(["x$v" for v in cluster], ", "))
        else
            println("  ", join(["x$v" for v in cluster[1:15]], ", "), " ... and $(length(cluster) - 15) more")
        end
    end

    length(clusters) > max_display && println("\n... and $(length(clusters) - max_display) more clusters")
end
