# Analysis of learned clause variables in the original tensor network

struct TensorNetworkMapping
    var_degrees::Vector{Int}                    # Variable degree in TN
    var_tensor_count::Vector{Int}               # Number of tensors containing each var
    high_freq_vars::Vector{Int}                 # Variables frequent in learned clauses
    high_freq_degrees::Vector{Int}              # Their degrees in TN
    tensor_distribution::Dict{Int, Vector{Int}}  # var → list of tensor indices
end

"""
Analyze how learned clause variables are distributed in the original tensor network.
This reveals whether CDCL is learning about high-degree vs low-degree variables,
and whether learned clauses connect previously distant parts of the network.
"""
function analyze_learned_in_tensor_network(
    learned_clauses::Vector{Vector{Int}},
    learned_lbds::Vector{Int},
    problem::TNProblem;
    top_k::Int=50
)
    nvars = length(problem.static.vars)
    cn = problem.static

    # Get variable degrees from original tensor network
    var_degrees = [v.deg for v in cn.vars]
    var_tensor_count = [length(cn.v2t[i]) for i in 1:nvars]

    # Count variable frequency in learned clauses
    var_freq_in_learned = zeros(Int, nvars)
    for clause in learned_clauses
        for lit in clause
            var = abs(lit)
            var <= nvars && (var_freq_in_learned[var] += 1)
        end
    end

    # Get high-frequency variables from learned clauses
    high_freq_indices = sortperm(var_freq_in_learned, rev=true)[1:min(top_k, nvars)]
    high_freq_vars = high_freq_indices[var_freq_in_learned[high_freq_indices] .> 0]
    high_freq_degrees = var_degrees[high_freq_vars]

    # Build tensor distribution for high-freq vars
    tensor_dist = Dict{Int, Vector{Int}}()
    for var in high_freq_vars
        tensor_dist[var] = cn.v2t[var]
    end

    return TensorNetworkMapping(
        var_degrees, var_tensor_count,
        high_freq_vars, high_freq_degrees,
        tensor_dist
    )
end

function print_tensor_network_analysis(
    mapping::TensorNetworkMapping,
    learned_stats::LearnedClauseStats;
    top_k::Int=20
)
    println("\n" * "=" ^ 70)
    println("Learned Clause Variables in Tensor Network")
    println("=" ^ 70)

    # Overall statistics
    println("\nTensor Network Statistics:")
    println("  Total variables: ", length(mapping.var_degrees))
    println("  Avg variable degree: ", round(mean(mapping.var_degrees), digits=2))
    println("  Max variable degree: ", maximum(mapping.var_degrees))
    println("  Min variable degree: ", minimum(mapping.var_degrees))

    # High-frequency learned variables
    println("\n" * "=" ^ 70)
    println("High-Frequency Learned Variables (Top $top_k)")
    println("=" ^ 70)
    println("Variables that appear frequently in learned clauses\n")

    println("Var ID | Learned Freq | TN Degree | Tensor Count | Category")
    println("-" ^ 70)

    for i in 1:min(top_k, length(mapping.high_freq_vars))
        var = mapping.high_freq_vars[i]
        learned_freq = learned_stats.var_frequency[var]
        tn_degree = mapping.var_degrees[var]
        tensor_count = mapping.var_tensor_count[var]

        # Categorize by degree
        category = if tn_degree >= 10
            "High-degree"
        elseif tn_degree >= 5
            "Medium-degree"
        elseif tn_degree >= 2
            "Low-degree"
        else
            "Isolated"
        end

        println("  x$var: $learned_freq times | deg $tn_degree | $tensor_count tensors | $category")
    end

    # Degree distribution analysis
    println("\n" * "=" ^ 70)
    println("Degree Distribution Analysis")
    println("=" ^ 70)

    high_freq_vars = mapping.high_freq_vars
    high_freq_degrees = mapping.high_freq_degrees

    println("\nLearned clause variables by degree category:")

    # Categorize
    isolated = sum(high_freq_degrees .== 1)
    low = sum(2 .<= high_freq_degrees .< 5)
    medium = sum(5 .<= high_freq_degrees .< 10)
    high = sum(high_freq_degrees .>= 10)

    total = length(high_freq_degrees)
    println("  Isolated (deg=1): $isolated / $total ($(round(100*isolated/total, digits=1))%)")
    println("  Low (2≤deg<5): $low / $total ($(round(100*low/total, digits=1))%)")
    println("  Medium (5≤deg<10): $medium / $total ($(round(100*medium/total, digits=1))%)")
    println("  High (deg≥10): $high / $total ($(round(100*high/total, digits=1))%)")

    println("\nAverage degree of learned variables: ", round(mean(high_freq_degrees), digits=2))
    println("Average degree of all variables: ", round(mean(mapping.var_degrees), digits=2))

    # Check if learned variables are more connected than average
    if mean(high_freq_degrees) > mean(mapping.var_degrees) * 1.2
        println("\n⚠ Learned variables are significantly MORE connected than average!")
        println("  → CDCL is learning about central, highly-connected variables")
    elseif mean(high_freq_degrees) < mean(mapping.var_degrees) * 0.8
        println("\n⚠ Learned variables are significantly LESS connected than average!")
        println("  → CDCL is learning about peripheral, weakly-connected variables")
    else
        println("\n✓ Learned variables have similar connectivity to the average")
    end
end

"""
Analyze tensor connectivity for learned clause variables.
Shows which tensors contain multiple high-frequency learned variables.
"""
function analyze_tensor_connectivity(
    mapping::TensorNetworkMapping,
    problem::TNProblem;
    min_overlap::Int=2
)
    println("\n" * "=" ^ 70)
    println("Tensor Connectivity Analysis")
    println("=" ^ 70)
    println("Tensors containing multiple high-frequency learned variables\n")

    cn = problem.static
    high_freq_set = Set(mapping.high_freq_vars)

    # For each tensor, count how many high-freq vars it contains
    tensor_overlap_counts = []

    for (tensor_idx, tensor) in enumerate(cn.tensors)
        overlap_count = count(v in high_freq_set for v in tensor.var_axes)
        if overlap_count >= min_overlap
            push!(tensor_overlap_counts, (tensor_idx, tensor, overlap_count))
        end
    end

    # Sort by overlap count
    sort!(tensor_overlap_counts, by=x->x[3], rev=true)

    println("Found $(length(tensor_overlap_counts)) tensors with ≥$min_overlap high-freq variables")

    if !isempty(tensor_overlap_counts)
        println("\nTop 15 tensors:")
        println("Tensor ID | Variables | High-Freq Var Count")
        println("-" ^ 60)

        for i in 1:min(15, length(tensor_overlap_counts))
            (tensor_idx, tensor, count) = tensor_overlap_counts[i]
            var_str = join(["x$v" for v in tensor.var_axes], ", ")
            if length(var_str) > 40
                var_str = var_str[1:37] * "..."
            end
            println("  T$tensor_idx: [$var_str] ($count vars)")
        end
    end

    return tensor_overlap_counts
end

"""
Check if learned binary/ternary clauses connect variables that are NOT in same tensor.
This reveals whether CDCL is learning "long-range" constraints.
"""
function analyze_clause_novelty(
    learned_clauses::Vector{Vector{Int}},
    learned_lbds::Vector{Int},
    problem::TNProblem
)
    println("\n" * "=" ^ 70)
    println("Learned Clause Novelty Analysis")
    println("=" ^ 70)

    cn = problem.static

    # Get short, high-quality clauses
    short_clauses = [
        clause for (clause, lbd) in zip(learned_clauses, learned_lbds)
        if 2 <= length(clause) <= 3 && lbd <= 3
    ]

    println("Analyzing $(length(short_clauses)) short clauses (length 2-3, LBD ≤ 3)\n")

    # Check if clause variables co-occur in existing tensors
    novel_clauses = []
    existing_clauses = []

    for clause in short_clauses
        clause_vars = Set(abs.(clause))

        # Check if any existing tensor contains all these variables
        is_novel = true
        for tensor in cn.tensors
            tensor_vars = Set(tensor.var_axes)
            if clause_vars ⊆ tensor_vars
                is_novel = false
                break
            end
        end

        if is_novel
            push!(novel_clauses, clause)
        else
            push!(existing_clauses, clause)
        end
    end

    println("Novel clauses (connect vars not in same tensor): $(length(novel_clauses))")
    println("Existing clauses (vars already in same tensor): $(length(existing_clauses))")
    println("\nNovelty ratio: $(round(100 * length(novel_clauses) / length(short_clauses), digits=1))%")

    if length(novel_clauses) > 0
        println("\n⚠ CDCL is discovering NEW constraints not in original tensor network!")
        println("  These are long-range dependencies worth adding as tensors.\n")

        println("Example novel clauses (first 10):")
        for i in 1:min(10, length(novel_clauses))
            println("  ", novel_clauses[i])
        end
    else
        println("\n✓ All learned clauses are subsumed by existing tensors")
        println("  (CDCL is rediscovering what tensor network already knows)")
    end

    return (novel=novel_clauses, existing=existing_clauses)
end
