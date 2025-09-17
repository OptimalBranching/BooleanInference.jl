# Exact BMF helpers
function down_closure(I::BitMatrix, D::Vector{Int})
    C = Int[x for x in 1:size(I, 1) if all(I[x, y] == 1 for y in D)]
    return C
end

function up_closure(I::BitMatrix, C::Vector{Int})
    D = Int[y for y in 1:size(I, 2) if all(I[x, y] == 1 for x in C)]
    return D
end

function restore_matrix(F::Set{Tuple{Vector{Int}, Vector{Int}}}, m::Int, n::Int)
    C = zeros(Bool, m, length(F))
    D = zeros(Bool, length(F), n)
    for (idx, (C_cols, D_rows)) in enumerate(F)
        for col in 1:length(C_cols)
            for row in C_cols[col]
                C[row, idx] = true
            end
        end
        for col in 1:length(D_rows)
            for row in D_rows[col]
                D[idx, row] = true
            end
        end
    end
    return Matrix{TropicalAndOr}(C), Matrix{TropicalAndOr}(D)
end

function find_formal_concepts(I::Matrix{TropicalAndOr})
    I = getproperty.(I, :n)
    U = I .== 1
    F = Set{Tuple{Vector{Int}, Vector{Int}}}()
    while sum(U) > 0
        j_list = collect(1: size(I, 2))
        best_V = 0
        best_C, best_D, best_j = Int[], Int[], nothing
        for j in j_list
            if j ∉ best_D
                C_temp = down_closure(I, vcat(best_D, Int[j]))
                D_temp = up_closure(I, C_temp)
                V_temp = compute_coverage_matrix((C_temp, D_temp), U)
                if V_temp > best_V
                    best_V, best_C, best_D, best_j = V_temp, C_temp, D_temp, j
                end
            end
        end
        push!(F, (best_C, best_D))
        U[best_C, best_D] .= false 
    end
    return restore_matrix(F, size(I, 1), size(I, 2))
end

function compute_coverage_matrix(concepts::Tuple{Vector{Int}, Vector{Int}}, U::BitMatrix)
    covered = falses(size(U))
    covered[concepts[1], concepts[2]] .= true  
    coverage_ratio = sum(covered .& U)
    return coverage_ratio
end




