using CairoMakie

# --- 数据 ---

# 第一组
x1 = [20, 24, 28, 32, 36, 40]
y1 = [48.88, 60.13, 71.7175, 83.40, 95.76, 105.31]

# 第二组（补 NaN 断线）
x2 = [20, 24, 28, 32, 36, 40]
y2 = [17.33, 19.945, 23.02, 25.57, NaN, NaN]

# 第三组
# x3 = [20, 24, 28, 32, 36, 40]
# y3 = [620, 888, 1204, 1568, 1980, 2440]

# --- 绘图 ---

f = Figure(resolution = (800, 500))
ax = Axis(f[1, 1], xlabel = "Semiprime length (bits)", ylabel = "Vars", title = "Avg. propagate vars")

# Group 1
l1 = lines!(ax, x1, y1, label = "Most Occurrence")
scatter!(ax, x1, y1)

# Group 2
l2 = lines!(ax, x2, y2, label = "Min Gamma")
scatter!(ax, x2[1:4], y2[1:4])  # 只给前3个点加 marker

# Group 3
# lines!(ax, x3, y3, label = "Group 3")
# scatter!(ax, x3, y3)

Legend(f[1, 1],
    [l1, l2],
    ["Most Occurrence", "Min Gamma"],
    halign = :right, valign = :bottom,
    tellwidth = false, tellheight = false
)

f