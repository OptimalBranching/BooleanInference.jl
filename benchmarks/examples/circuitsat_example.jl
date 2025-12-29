#=
CircuitSAT Benchmarking Example
================================
=#

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using BooleanInferenceBenchmarks
using BooleanInference: MostOccurrenceSelector, NumUnfixedVars, NumHardTensors
using Statistics: median

println("="^60)
println("CircuitSAT Benchmarks")
println("="^60)

# ============================================================================
# Solve with default solver
# ============================================================================
println("\n📁 Solve with default solver")
println("-"^40)

path = joinpath(@__DIR__, "..", "data", "iscas85", "c17.v")
if isfile(path)
    result = solve(path)
    println("c17: $(result.status) | $(round(result.time, digits=3))s | $(result.branches) branches")
end

println("\n🔧 Compare Solvers")
println("-"^40)

# path = joinpath(@__DIR__, "..", "data", "iscas85", "c7552.v")
path = joinpath(@__DIR__, "..", "data", "aig", "non-arithmetic", "b14.aag")
if isfile(path)
    circuit = load(path)

    # solver = Solvers.BI(selector=MostOccurrenceSelector(3, 4))
    # r = solve(circuit, solver=solver)
    # println("MostOcc(3,4): $(r.status) | $(round(r.time, digits=3))s | $(r.branches) branches")

    # Kissat comparison
    r = solve(circuit, solver=Solvers.Kissat())
    println("Kissat: $(r.status) | $(round(r.time, digits=3))s | $(r.branches) decisions")

    r = solve(circuit, solver=Solvers.Minisat())
    println("MiniSat: $(r.status) | $(round(r.time, digits=3))s | $(r.branches) decisions")
end

# ============================================================================
# Benchmark directory
# ============================================================================
println("\n📊 Benchmark ISCAS85 dataset")
println("-"^40)

iscas_dir = joinpath(@__DIR__, "..", "data", "iscas85")
if isdir(iscas_dir)
    res = benchmark(iscas_dir, verbose=false)
    sat_count = count(r -> r.status == SAT, res.results)
    unsat_count = count(r -> r.status == UNSAT, res.results)
    println("Instances: $(length(res.times)) (SAT: $sat_count, UNSAT: $unsat_count)")
    println("Median time: $(round(median(res.times), digits=4))s")
    println("Total branches: $(sum(res.branches))")
end

println("\n" * "="^60)
println("✅ Examples Complete!")
println("="^60)
