using ..BooleanInferenceBenchmarks: AbstractSolver, AbstractBenchmarkProblem, AbstractProblemConfig
using Gurobi

struct BooleanInferenceSolver <: AbstractSolver end

struct IPSolver <: AbstractSolver 
    optimizer::Any
    env::Any
    function IPSolver(optimizer=Gurobi.Optimizer, env=nothing)
        new(optimizer, env)
    end
end

struct FactoringProblem <: AbstractBenchmarkProblem end

struct FactoringConfig <: AbstractProblemConfig
    m::Int
    n::Int
end

