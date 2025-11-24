using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using ProblemReductions

dataset_path = joinpath(@__DIR__, "..", "data", "CNF", "random")
cnf_files = discover_cnf_files(dataset_path)
println("Found $(length(cnf_files)) CNF files in $dataset_path:")
for file in cnf_files
    instance = parse_cnf_file(file)
    cnf = cnf_instantiation(instance)
end

result = benchmark_dataset(
    CNFSATProblem,
    dataset_path;
    solver=BooleanInferenceSolver(),
    verify=true
)

test_file = joinpath(dataset_path, "3sat1.cnf")
test_instance = parse_cnf_file(test_file)
result = solve_instance(CNFSATProblem, test_instance, BooleanInferenceSolver())
@show result