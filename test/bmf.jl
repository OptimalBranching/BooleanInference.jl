using TropicalNumbers
using Test 
using BooleanInference

@testset "MEBF" begin
    # This is an approximate algorithm for Boolean matrix factorization (BMF) based on the MBF algorithm.
    A = Matrix{TropicalAndOr}(BitMatrix(rand(0:1, 100, 100)))
    # MBF function contains 3 keyword arguments:
    # Dim: maximum number of patterns (k)
    # Thres: between 0 and 1. A smaller t could achieve higher coverage with less number of patterns, while a larger t enables a more sparse decomposition of the input matrix with greater number of patterns.
    # P: percentage of uncovered 1s
    B, C = MEBF(A)
end

@testset "factor analysis" begin
    # This is an exact algorithm for Boolean matrix factorization (BMF) based on the MBF algorithm.
    I = Matrix{TropicalAndOr}(BitMatrix(rand(0:1, 50, 50)))
    C, D = find_formal_concepts(I)
end
