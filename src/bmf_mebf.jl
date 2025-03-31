# This is an approximate algorithm for Boolean matrix factorization (BMF) based on the MBF algorithm.
function MEBF(MATₜ::Matrix{TropicalAndOr}; DIM::Int=1000, Thres::Float64=0.5, P::Float64=0.05)
    # This function is directly migrated from the R language code provided in the paper.  https://doi.org/10.1609/aaai.v34i04.6072
    # Source: https://github.com/clwan/MEBF.git
    # Dim: maximum number of patterns (k)
    # Thres: between 0 and 1. A smaller t could achieve higher coverage with less number of patterns, while a larger t enables a more sparse decomposition of the input matrix with greater number of patterns.
    # P: percentage of uncovered 1s
    MAT = getproperty.(MATₜ, :n)
    if min(size(MAT)...) < DIM
        DIM = min(size(MAT)...) - 1
    end

    m1 = copy(MAT)
    SUM = sum(MAT)
    MAT_B = Vector{Int}[]
    MAT_C = Vector{Int}[]

    for _ in 1:DIM
        if sum(m1) <= P * SUM
            @info "Uncovered percentage is lower than $P. No more growth possible."
            break
        
        end

        C1 = 0
        B1_use = zeros(Int, size(m1, 1))
        B2_use = zeros(Int, size(m1, 2))

        COL = vec(sum(m1, dims=1))  # column sum
        ROW = vec(sum(m1, dims=2))  # row sum

        if median(filter(x -> x > 0, COL)) > 1
            TEMP = findall(==(minimum(filter(x -> x >= median(filter(x -> x > 0, COL)), COL))), COL)
            for j in TEMP
                B1 = m1[:, j]
                B2 = zeros(Int, size(m1, 2))
                B2[findall(x -> x >= min(Thres * sum(B1) + 1, sum(B1)), vec(sum(m1[B1 .== 1, :], dims=1)))] .= 1        
                C2 = (sum(B1) - 1) * (sum(B2) - 1) - sum(m1[B1 .== 1, B2 .== 1] .== 0)
                if C2 > C1
                    C1 = C2
                    B1_use = B1
                    B2_use = B2
                end
            end
        end

        if median(filter(x -> x > 0, ROW)) > 1
            TEMP = findall(==(minimum(filter(x -> x >= median(filter(x -> x > 0, ROW)), ROW))), ROW)
            for j in TEMP
                B2 = m1[j, :]
                B1 = zeros(Int, size(m1, 1))
                B1[findall(x -> x >= min(Thres * sum(B2) + 1, sum(B2)), vec(sum(m1[:, B2 .== 1], dims=2)))] .= 1
                C2 = (sum(B1) - 1) * (sum(B2) - 1) - sum(m1[B1 .== 1, B2 .== 1] .== 0)
                if C2 > C1
                    C1 = C2
                    B1_use = B1
                    B2_use = B2
                end
            end
        end

        if C1 == 0
            ROW_ORDER = sortperm(ROW, rev=true)
            COL_ORDER = sortperm(COL, rev=true)

            B1_1 = zeros(Int, size(m1, 1))
            if count(x -> x == 2, sum(m1[:, COL_ORDER[1:2]], dims=2)) > 1
                B1_1[findall(x -> x == 2, sum(m1[:, COL_ORDER[1:2]], dims=2))] .= 1
                B1_2 = zeros(Int, size(m1, 2))
                B1_2[findall(x -> x >= min(Thres * sum(m1[B1_1 .== 1, COL_ORDER[1]]) + 1, sum(m1[B1_1 .== 1, COL_ORDER[1]])), vec(sum(m1[B1_1 .== 1, :], dims=1)))] .= 1
                C1 = (sum(B1_1) - 1) * (sum(B1_2) - 1) - sum(m1[B1_1 .== 1, B1_2 .== 1] .== 0)
            else
                C1 = -Inf
            end

            B2_2 = zeros(Int, size(m1, 2))
            if count(x -> x == 2, sum(m1[ROW_ORDER[1:2], :], dims=1)) > 1
                B2_2[findall(x -> x == 2, vec(sum(m1[ROW_ORDER[1:2], :], dims=1)))] .= 1
                B2_1 = zeros(Int, size(m1, 1))
                B2_1[findall(x -> x >= min(Thres * sum(m1[ROW_ORDER[1], B2_2 .== 1]) + 1, sum(m1[ROW_ORDER[1], B2_2 .== 1])), sum(m1[:, B2_2 .== 1], dims=2))] .= 1
                C2 = (sum(B2_1) - 1) * (sum(B2_2) - 1) - sum(m1[B2_1 .== 1, B2_2 .== 1] .== 0)
            else
                C2 = -Inf
            end

            if C1 == -Inf && C2 == -Inf
                break
            elseif C1 > C2
                B1_use = B1_1
                B2_use = B1_2
                m1[B1_1 .== 1, B1_2 .== 1] .= 0
            else
                B1_use = B2_1
                B2_use = B2_2
                m1[B2_1 .== 1, B2_2 .== 1] .= 0
            end
        end
        MAT_B = push!(MAT_B, B1_use)
        MAT_C = push!(MAT_C, B2_use)
        m1[B1_use .== 1, B2_use .== 1] .= 0
    end
    @info "MEBF finished. Number of patterns: $(length(MAT_B))"
    return (Matrix{TropicalAndOr}(BitMatrix(hcat(MAT_B...))), Matrix{TropicalAndOr}(BitMatrix(hcat(MAT_C...)')))
end

function median(arr)
    sorted_arr = sort(arr)
    n = length(sorted_arr)
    if n == 0
        error("Cannot compute median of an empty array")
    elseif isodd(n)
        return sorted_arr[(n ÷ 2) + 1]
    else
        return (sorted_arr[n ÷ 2] + sorted_arr[(n ÷ 2) + 1]) / 2
    end
end
