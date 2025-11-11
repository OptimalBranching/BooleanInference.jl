using CairoMakie

configs = ["10x10", "12x12", "14x14", "16x16", "18x18", "20x20", "22x22"]
sizes = [20, 24, 28, 32, 36, 40, 44, 48]

bi = [0.0671, 0.1093, 0.1547, 0.6152, 1.03, 2.67, 20.30, 143.7564948]
gurobi = [0.0675, 0.7289, 1.63, 7.6, NaN, NaN, NaN, NaN]
xsat = [0.0614, 0.1026, 0.1876, 0.3284, 1.26, 2.51, 11.32, 80.8]
minisat = [0.0418, 0.0527, 0.0747, 0.1004, 0.4886, 3.37, 17.07, 100.0]
kissat = [0.0474, 0.0594, 0.1101, 0.1867, 0.4970, 1.88, 6.35, 23.56]


f = Figure(resolution = (700, 450))
ax = Axis(f[1, 1];
    xlabel = "Semiprime length (bits)",
    ylabel = "Runtime (seconds)",
    title = "Runtime Comparison",
    yscale = log10, 
)

lines!(ax, sizes, bi; label = "BooleanInference", linewidth = 4, color = :red)
lines!(ax, sizes, gurobi; label = "IP-Gurobi", linewidth = 2, color = :black)
lines!(ax, sizes, xsat; label = "X-SAT", linewidth = 2, color = :orange)
lines!(ax, sizes, minisat; label = "MiniSAT", linewidth = 2, color = :blue)
lines!(ax, sizes, kissat; label = "Kissat", linewidth = 2, color = :green)

scatter!(ax, sizes, bi, color = :red)
scatter!(ax, sizes, gurobi, color = :black)
scatter!(ax, sizes, xsat, color = :orange)
scatter!(ax, sizes, minisat, color = :blue)
scatter!(ax, sizes, kissat, color = :green)
axislegend(ax; position = :lt)

scatter!(ax, [48], [600], color = :orange, marker = :circle, markersize = 6)
text!(ax, 48, 600, text = "xsat 1 timeout", align = (:right, :top), color = :orange)

save("runtime_comparison.png", f)
f