using TropicalNumbers
using Test 
using BooleanInference
using Random

@testset "MEBF" begin
    Random.seed!(1234)
    # This is an approximate algorithm for Boolean matrix factorization (BMF) based on the MBF algorithm.
    A = Matrix{TropicalAndOr}(BitMatrix(rand(0:1, 100, 100)))
    # MBF function contains 3 keyword arguments:
    # Dim: maximum number of patterns (k)
    # Thres: between 0 and 1. A smaller t could achieve higher coverage with less number of patterns, while a larger t enables a more sparse decomposition of the input matrix with greater number of patterns.
    # P: percentage of uncovered 1s
    B, C = MEBF(A;Thres=0.3)
    @show sum(B*C .== A)
    @show size(B,2)

    B, C = MEBF(A;Thres=0.5)
    @show sum(B*C .== A)
    @show size(B,2)

    B, C = MEBF(A;Thres=0.8)
    @show sum(B*C .== A)
    @show size(B,2)
end

@testset "factor analysis" begin
    Random.seed!(1234)
    # This is an exact algorithm for Boolean matrix factorization (BMF) based on the MBF algorithm.
    A = Matrix{TropicalAndOr}(BitMatrix(rand(0:1, 50, 50)))
    B, C = find_formal_concepts(A)
    @show sum(B*C .== A)
    @show size(B,2)
end

@testset "specific k" begin
    m = 50
    k= 10
    n = 50
    Random.seed!(1234)
    a = [TropicalAndOr(rand()>0.5) for i in 1:m, j in 1:k]
    b = [TropicalAndOr(rand()>0.5) for i in 1:k, j in 1:n]
    A = a*b
    B, C = find_formal_concepts(A)
    @show sum(B*C .== A)
    @show size(B,2)

    B, C = MEBF(A;Thres=0.8)
    @show sum(B*C .== A)
    @show size(B,2)
end

@testset "small_matrix" begin
    A = TropicalAndOr[true false; false true]
    B, C = MEBF(A)
end