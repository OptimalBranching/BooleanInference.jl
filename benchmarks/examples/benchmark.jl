using CairoMakie
using Statistics

bit_lengths = [16]  # 现在只有一个 scale，以后可以变成 [16, 20, 24, ...]

mingamma = [62, 8, 50, 34, 23, 49, 41, 21, 23, 44,
            40, 18, 30, 30, 16, 49, 58, 58, 29, 20]

mostoccurrence = [47, 44, 25, 21, 46, 46, 54, 36, 6, 17,
                  34, 38, 36, 16, 12, 18, 41, 41, 7, 18]

kissat = [49, 36, 18, 80, 14, 85, 10, 24, 47, 0,
          0, 3, 3, 36, 0, 44, 7, 7, 25, 14]

minisat = [62, 61, 40, 70, 52, 96, 89, 36, 76, 6,
           10, 61, 43, 155, 74, 11, 73, 73, 15, 77]

# Helper function: mean and std for a group of instances
function mean_and_err(values)
    m = mean(values)
    err = std(values)  # or std(values) / sqrt(length(values)) for std error
    return m, err
end

m_mingamma, err_mingamma = mean_and_err(mingamma)
m_most, err_most         = mean_and_err(mostoccurrence)
m_kissat, err_kissat     = mean_and_err(kissat)
m_minisat, err_minisat   = mean_and_err(minisat)

f = Figure()
ax = Axis(f[1, 1],
    xlabel = "bit length",
    ylabel = "runtime (or your metric)",
    title = "Performance vs bit length with error bars",
)

# For now we only have one bit length, so each algo has just one mean value.
bit_lengths = [16]

mingamma_means = [m_mingamma]
mingamma_errs  = [err_mingamma]

most_means = [m_most]
most_errs  = [err_most]

kissat_means = [m_kissat]
kissat_errs  = [err_kissat]

minisat_means = [m_minisat]
minisat_errs  = [err_minisat]

# Plot lines + error bars for each algorithm
lines!(ax, bit_lengths, mingamma_means, label = "MinGamma")
errorbars!(ax, bit_lengths, mingamma_means, mingamma_errs, mingamma_errs)

lines!(ax, bit_lengths, most_means, label = "MostOccurrence")
errorbars!(ax, bit_lengths, most_means, most_errs, most_errs)

lines!(ax, bit_lengths, kissat_means, label = "Kissat")
errorbars!(ax, bit_lengths, kissat_means, kissat_errs, kissat_errs)

lines!(ax, bit_lengths, minisat_means, label = "MiniSat")
errorbars!(ax, bit_lengths, minisat_means, minisat_errs, minisat_errs)

axislegend(ax)
f
# save("performance_vs_bitlength.png", f)