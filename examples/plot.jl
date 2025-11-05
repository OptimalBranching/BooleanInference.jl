using CairoMakie

configs = ["10x10", "12x12", "14x14", "16x16", "18x18", "20x20", "22x22"]
sizes = [20, 24, 28, 32, 36, 40, 44]

bi = [0.0671, 0.1093, 0.1547, 0.6152, 1.03, 2.67, 20.30]
gurobi = [0.0675, 0.7289, 1.63, 7.6, NaN, NaN, NaN]
xsat = [0.0614, 0.1026, 0.1876, 0.3284, 1.26, 2.51, 11.32]


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