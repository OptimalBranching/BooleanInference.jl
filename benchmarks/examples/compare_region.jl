using CairoMakie
using Statistics

# ========== 1. Prepare data in "long" format ==========
# Each row (scale, n, perf) is one sample.

scales = Int[]
ns     = Int[]
perfs  = Float64[]

# Helper function to add data for one (scale, n)
function add_data!(scales, ns, perfs, scale::Int, n::Int, values::Vector{<:Real})
    for v in values
        push!(scales, scale)
        push!(ns, n)
        push!(perfs, float(v))
    end
end

# --------- Fill your data here ---------
# scale = 16
data1 = [100, 76, 56, 24, 88, 82, 99, 47, 28, 45, 54, 64, 53, 62, 29, 31, 69, 69, 16, 37]
data2 = [62, 8, 50, 34, 23, 49, 41, 21, 23, 44, 40, 18, 30, 30, 16, 49, 58, 58, 29, 20]
data3 = [50, 11, 29, 28, 31, 67, 42, 38, 31, 43, 46, 11, 41, 23, 17, 30, 37, 37, 30, 22]
data4 = [55, 9, 15, 22, 16, 49, 58, 34, 25, 38, 45, 12, 35, 24, 28, 15, 44, 44, 31, 17]
data5 = [40, 31, 41, 24, 11, 40, 35, 17, 18, 32, 19, 12, 15, 24, 21, 16, 33, 33, 39, 20]
add_data!(scales, ns, perfs, 16, 1, data1)          # n = 1: 100, 76, ...
add_data!(scales, ns, perfs, 16, 2, data2)            # n = 2: 62, 8, ...
add_data!(scales, ns, perfs, 16, 3, data3)           # n = 3: 50, 11, ...
add_data!(scales, ns, perfs, 16, 4, data4)            # n = 4: 55, 9, ...
add_data!(scales, ns, perfs, 16, 5, data5)           # n = 5: 40, 31, ...

#kissat
kissat16 = [49, 36, 18, 80, 14, 85, 10, 24, 47, 0, 0, 3, 3, 36, 0, 44, 7, 7, 25, 14]
minisat16 = [62, 61, 40, 70, 52, 96, 89, 36, 76, 6, 10, 61, 43, 155, 74, 11, 73, 73, 15, 77]

# scale = 20
data1 = [130, 158, 230, 79, 83, 189, 103, 352, 31, 106, 143, 199, 64, 63, 133, 150, 36, 176, 29, 43]
data2 = [124, 136, 238, 69, 53, 94, 98, 158, 35, 287, 76, 130, 257, 48, 68, 82, 31, 113, 29, 36]
data3 = [113, 130, 134, 160, 52, 46, 55, 158, 53, 54, 107, 153, 255, 69, 85, 40, 34, 146, 69, 39]
data4 = [138, 172, 69, 119, 30, 89, 45, 154, 37, 269, 157, 137, 181, 44, 25, 37, 30, 76, 52, 45]
data5 = [243, 125, 172, 48, 25, 30, 86, 105, 38, 142, 126, 115, 48, 39, 58, 46, 27, 55, 24, 25]
add_data!(scales, ns, perfs, 20, 1, data1)         # n = 1: 130, 158, ...
add_data!(scales, ns, perfs, 20, 2, data2)         # n = 2: 124, 136, ...
add_data!(scales, ns, perfs, 20, 3, data3)         # n = 3: 113, 130, ...
add_data!(scales, ns, perfs, 20, 4, data4)         # n = 4: 138, 172, ...
add_data!(scales, ns, perfs, 20, 5, data5)         # n = 5: 243, 125, ...

# kissat
kissat20 = [37, 20, 0, 557, 67, 27, 352, 35, 239, 239, 62, 593, 291, 195, 38, 0, 492, 39, 309, 485]
minisat20 = [111, 157, 343, 273, 165, 217, 312, 239, 31, 510, 79, 731, 323, 106, 73, 30, 429, 30, 362, 109]

# scale = 24
data1 = [1243, 3932, 1068, 1054, 94, 383, 852, 363, 1382, 700, 1798, 125, 138, 47, 1860, 982, 194, 2083, 1878, 615]
data2 = [612, 1030, 1520, 709, 480, 361, 602, 341, 1012, 865, 1373, 93, 79, 50, 355, 790, 158, 1352, 925, 404]
data3 = [313, 1861, 1229, 234, 54, 165, 604, 66, 381, 949, 994, 99, 56, 49, 348, 734, 548, 1108, 459, 498]
data4 = [348, 2002, 253, 723, 94, 303, 434, 56, 249, 858, 1015, 51, 55, 61, 355, 39, 66, 1022, 490, 334]
data5 = [216, 962, 577, 411, 84, 378, 249, 45, 64, 403, 545, 33, 297, 55, 330, 256, 119, 1816, 1177, 522]
add_data!(scales, ns, perfs, 24, 1, data1)         # n = 1: 1243, 3932, ...
add_data!(scales, ns, perfs, 24, 2, data2)         # n = 2: 612, 1030, ...
add_data!(scales, ns, perfs, 24, 3, data3)         # n = 3: 313, 1861, ...
add_data!(scales, ns, perfs, 24, 4, data4)
add_data!(scales, ns, perfs, 24, 5, data5)

#kissat
kissat24 = [538, 2414, 62, 335, 395, 1226, 22, 0, 546, 1788, 2724, 343, 1733, 2227, 2381, 1982, 2136, 2784, 1913, 1006]
minisat24 = [716, 1758, 843, 1175, 627, 712, 282, 280, 89, 320, 1983, 88, 1605, 1843, 1097, 1123, 470, 362, 1109, 1342]

# ========== 2. Make a faceted boxplot by scale ==========

baseline_dict = Dict(
    16 => [mean(kissat16), mean(minisat16)],      # baseline 1 & baseline 2 for scale 16
    20 => [mean(kissat20), mean(minisat20)],    # baseline 1 & baseline 2 for scale 20
    24 => [mean(kissat24), mean(minisat24)],    # baseline 1 & baseline 2 for scale 24
)

unique_scales = sort(unique(scales))
n_scales = length(unique_scales)

colors = [:red, :blue, :green, :orange, :purple]
linestyles = [:dash, :dot, :dashdot, :dash, :dot]

# Adjust resolution depending on how many scales you have
fig = Figure(resolution = (350 * n_scales, 400))

for (i, sc) in enumerate(unique_scales)
    ax = Axis(fig[1, i];
        title  = "Bit length = $sc",
        xlabel = "Region size n",
        ylabel = "Branch number"
    )

    # Select data for this scale
    idx = findall(j -> scales[j] == sc, eachindex(scales))
    xs  = ns[idx]      # n values (group variable)
    ys  = perfs[idx]   # performance values

    # Boxplot: group by xs, values = ys
    boxplot!(ax, xs, ys)

    xleft, xright = 0.5, maximum(xs) + 0.5

    for (bi, b) in enumerate(baseline_dict[sc])
        lines!(
            ax,
            [xleft, xright], [b, b]; 
            color     = colors[(bi - 1) % length(colors) + 1],
            linestyle = linestyles[(bi - 1) % length(linestyles) + 1],
            linewidth = 2
        )
    end

    # Nice x ticks: only show n that appear in this scale
    unique_ns = sort(unique(xs))
    ax.xticks = (unique_ns, string.(unique_ns))
end

save("boxplot_region.png", fig)
fig

