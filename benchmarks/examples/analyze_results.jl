using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BooleanInferenceBenchmarks
using Statistics

result_dir = resolve_results_dir("factoring")

# 示例 1: 读取某个数据集的所有结果
println("="^80)
println("示例 1: 读取 numbers_8x8 数据集的所有结果")
println("="^80)

results_8x8 = load_dataset_results(result_dir, "numbers_8x8")
println("找到 $(length(results_8x8)) 个结果")

for (i, result) in enumerate(results_8x8)
    println("\n结果 $i:")
    print_result_summary(result)
end

# 示例 2: 读取所有结果并比较
println("\n")
println("="^80)
println("示例 2: 读取所有结果并比较")
println("="^80)

all_results = load_all_results(result_dir)
println("总共找到 $(length(all_results)) 个结果")

compare_results(all_results)

# 示例 3: 筛选特定求解器的结果
println("\n")
println("="^80)
println("示例 3: 只看 BooleanInference 求解器的结果")
println("="^80)

bi_results = filter_results(all_results, solver_name="BI")
println("找到 $(length(bi_results)) 个 BI 求解器的结果")

compare_results(bi_results)

# 示例 3.5: 详细比较 BI 求解器的不同配置
println("\n")
println("="^80)
println("示例 3.5: 详细查看 BI 求解器在 numbers_10x10 上的不同配置")
println("="^80)

bi_10x10 = filter_results(bi_results, dataset="numbers_10x10")
print_detailed_comparison(bi_10x10)

# 示例 4: 筛选特定数据集和求解器
println("\n")
println("="^80)
println("示例 4: 查看 numbers_10x10 数据集上的所有结果")
println("="^80)

results_10x10 = filter_results(all_results, dataset="numbers_10x10")
compare_results(results_10x10)

# 示例 5: 找到最快的配置
println("\n")
println("="^80)
println("示例 5: 找到每个数据集上最快的配置")
println("="^80)

datasets = unique([splitext(basename(r.dataset_path))[1] for r in all_results])
for dataset in sort(datasets)
    dataset_results = filter_results(all_results, dataset=dataset)
    if !isempty(dataset_results)
        best = argmin([mean(r.times) for r in dataset_results])
        best_result = dataset_results[best]
        println("\n$dataset: $(best_result.solver_name) - Mean time: $(round(mean(best_result.times), digits=4))s")
        
        # 打印配置
        println("  Configuration:")
        for k in sort(collect(keys(best_result.solver_config)))
            println("    $k: $(best_result.solver_config[k])")
        end
    end
end

