using BooleanInference

# 1. Instantiate the logger
logger = BranchingLogger()

# 2. Run a small factoring problem with the logger
# Factoring 15 = 3 * 5
# n=4 bits, m=4 bits, N=15
println("Solving factoring problem...")
a, b, stats = solve_factoring(20,20,694480512097; logger=logger)

println("\nSolution found: $a * $b = $(a*b)")

# 3. View high-level summary
println("\n--- Logger Summary ---")
print_logger_summary(logger)

# 4. Access detailed logs
println("\n--- Detailed Logs (First 3) ---")
data = export_logs(logger)
for (i, entry) in enumerate(first(data, 3))
    println("Decision $i:")
    println("  Depth: ", entry.depth)
    println("  Region: $(entry.region_vars) vars, $(entry.region_tensors) tensors")
    println("  Support Size: ", entry.support_size)
    println("  Branches: ", entry.branch_count)
    println("  Prop Time: ", round(entry.prop_time_ns / 1e3, digits=1), " µs")
end

if isempty(data)
    println("(No branching happened - problem might be too simple)")
end

# 5. NEW: Visualize as tree diagram
println("\n--- Tree Visualization ---")

# ASCII tree in terminal
# visualize_tree(logger; show_details=true, max_depth=10)

# Generate interactive HTML visualization
html_path = joinpath(@__DIR__, "branching_tree.html")
visualize_tree(logger; html=html_path)
println("\nOpen '$html_path' in a browser to see interactive visualization!")
