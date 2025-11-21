using BooleanInference
using Test

@testset "branch.jl" begin
    include("branch.jl")
end

@testset "contraction.jl" begin
    include("contraction.jl")
end

@testset "interface.jl" begin
    include("interface.jl")
end

@testset "knn.jl" begin
    include("knn.jl")
end

@testset "problems.jl" begin
    include("problems.jl")
end

@testset "propagate.jl" begin
    include("propagate.jl")
end

@testset "greedymerge.jl" begin
    include("greedymerge.jl")
end

@testset "circuit_analysis.jl" begin
    include("circuit_analysis.jl")
end

@testset "branchtable.jl" begin
    include("branchtable.jl")
end