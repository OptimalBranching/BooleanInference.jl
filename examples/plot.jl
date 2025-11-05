using CairoMakie

configs = ["10x10", "12x12", "14x14", "16x16", "18x18", "20x20", "22x22"]
sizes = [20, 24, 28, 32, 36, 40, 44]

bi = [0.0804, 0.1761, 0.4815, 1.93, 8.88, 40.99, 267.323853]
gurobi = [0.0675, 0.7289, 1.63, 7.6, NaN, NaN, NaN]
xsat = [0.0650, 0.1069, 0.1832, 0.3375, 1.42, 5.21, 38.826105999999996]


f = Figure(resolution = (700, 450))
ax = Axis(f[1, 1];
    xlabel = "Semiprime length (bits)",
    ylabel = "Runtime (seconds)",
    title = "Runtime Comparison",
    yscale = log10, 
)

lines!(ax, sizes, bi; label = "BooleanInference", linewidth = 2)
lines!(ax, sizes, gurobi; label = "IP-Gurobi", linewidth = 2)
lines!(ax, sizes, xsat; label = "X-SAT", linewidth = 2, color = :red)

scatter!(ax, sizes, bi)
scatter!(ax, sizes, gurobi)
scatter!(ax, sizes, xsat; color = :red)

axislegend(ax; position = :lt)

save("runtime_comparison.png", f)
f