#=
BooleanInferenceBenchmarks - Quick Start
========================================
=#

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using BooleanInferenceBenchmarks
using BooleanInference: MostOccurrenceSelector
using Statistics: median

println("="^60)
println("BooleanInferenceBenchmarks")
println("="^60)

# ============================================================================
# 1. Solve a Circuit
# ============================================================================
println("\n📁 Solve a Circuit")
println("-"^40)

path = joinpath(@__DIR__, "..", "data", "iscas85", "c17.v")
if isfile(path)
    result = solve(path)
    println("Status: $(result.status), Time: $(round(result.time, digits=3))s, Branches: $(result.branches)")
else
    println("File not found: $path")
end

# ============================================================================
# 2. Custom Solver Configuration
# ============================================================================
println("\n🔧 Custom Solver")
println("-"^40)

path = joinpath(@__DIR__, "..", "data", "iscas85", "c432.v")
if isfile(path)
    circuit = load(path)

    # Custom selector parameters
    solver = Solvers.BI(selector=MostOccurrenceSelector(4, 8), show_stats=false)
    r = solve(circuit, solver=solver)
    println("BI(4,8): $(r.status) | $(round(r.time, digits=3))s | $(r.branches) branches")

    # Kissat
    r = solve(circuit, solver=Solvers.Kissat())
    println("Kissat: $(r.status) | $(round(r.time, digits=3))s | $(r.branches) decisions")
end

# ============================================================================
# 3. Benchmark
# ============================================================================
println("\n📊 Benchmark")
println("-"^40)

iscas_dir = joinpath(@__DIR__, "..", "data", "iscas85")
if isdir(iscas_dir)
    res = benchmark(iscas_dir, verbose=false)
    println("Instances: $(length(res.times))")
    println("Median time: $(round(median(res.times), digits=4))s")
    println("Total branches: $(sum(res.branches))")
end

println("\n" * "="^60)
println("""
API:
  load("file.v")                      # Load
  solve("file.v")                     # Load + solve
  solve(inst, solver=Solvers.BI())    # Custom solver
  benchmark("dir/")                   # Benchmark

Solvers.BI() parameters:
  selector         = MostOccurrenceSelector(3, 6)
  measure          = NumUnfixedVars()
  set_cover_solver = GreedyMerge()
  show_stats       = false
  use_cdcl         = true
  conflict_limit   = 40000
  max_clause_len   = 5
""")
println("="^60)
