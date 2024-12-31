using BooleanInference
using Test

@testset "interface.jl" begin
    include("interface.jl")
end

@testset "reducer.jl" begin
    include("reducer.jl")
end

@testset "selector.jl" begin
    include("selector.jl")
end


@testset "branch.jl" begin
    include("branch.jl")
end

@testset "status.jl" begin
    include("status.jl")
end

@testset "tablesolver.jl" begin
    include("tablesolver.jl")
end

@testset "stride.jl" begin
    include("stride.jl")
end