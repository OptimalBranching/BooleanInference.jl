using Test
using BooleanInference
using BooleanInference: NumUnfixedVars, DetailedStats
using BooleanInference: record_depth!, record_branch!, record_unsat_leaf!, record_solved_leaf!, record_skipped_subproblem!
using BooleanInference: record_propagation!, record_domain_reduction!, record_early_unsat!
using BooleanInference: record_branching_time!, record_contraction_time!, record_filtering_time!, record_cache_hit!, record_cache_miss!
using BooleanInference: record_variable_selection!, record_successful_path!
using BooleanInference: reset!

@testset "BranchingStats detailed metrics" begin
    stats = BranchingStats(true)
    @test BooleanInference.needs_path_tracking(stats)
    @test stats.avg_branching_factor == 0.0

    record_branch!(stats, 3, 2)
    record_branch!(stats, 2, 1)

    @test stats.total_branches == 2
    @test stats.total_subproblems == 5
    @test stats.max_depth == 2
    @test stats.avg_branching_factor ≈ 2.5

    d = stats.detailed
    @test d.branching_factors == [3, 2]
    @test d.depth_distribution[3] == 1
    @test d.depth_distribution[2] == 1

    record_propagation!(stats, 0.25)
    record_propagation!(stats, 0.5)
    @test d.propagation_calls == 2
    @test d.time_propagation ≈ 0.75

    record_domain_reduction!(stats, 7)
    record_early_unsat!(stats)
    @test d.domain_reductions == 7
    @test d.early_unsat_detections == 1

    record_branching_time!(stats, 0.1)
    record_contraction_time!(stats, 0.2)
    record_filtering_time!(stats, 0.3)
    @test d.time_branching ≈ 0.1
    @test d.time_contraction ≈ 0.2
    @test d.time_filtering ≈ 0.3

    record_cache_hit!(stats)
    record_cache_hit!(stats)
    record_cache_miss!(stats)
    @test d.cache_hits == 2
    @test d.cache_misses == 1

    record_variable_selection!(stats, 5, 10, 2)
    record_variable_selection!(stats, 5, 6, 1)
    record_variable_selection!(stats, 7, 4, 0)
    @test d.variable_selection_counts[5] == 2
    @test d.variable_selection_counts[7] == 1
    @test d.remaining_vars_at_branch == [10, 6, 4]
    @test d.depth_at_selection == [2, 1, 0]
    @test d.variable_selection_sequence == [5, 5, 7]

    record_successful_path!(stats, [1, 2, 3])
    @test !isempty(d.successful_paths)
    @test d.successful_paths[1] == [1, 2, 3]

    record_unsat_leaf!(stats, 4)
    @test stats.max_depth == 4

    record_skipped_subproblem!(stats)

    buf = IOBuffer()
    print_stats_summary(stats; io=buf)
    summary_output = String(take!(buf))
    @test occursin("Branch decisions: 2", summary_output)
    @test occursin("Successful paths", summary_output)

    copied = copy(stats)
    @test copied !== stats
    @test copied.detailed !== d
    @test copied.detailed.successful_paths[1] == d.successful_paths[1]
    copied.detailed.successful_paths[1][1] = 99
    @test d.successful_paths[1][1] == 1

    reset!(stats)
    @test stats.total_branches == 0
    @test stats.total_subproblems == 0
    @test stats.max_depth == 0
    @test stats.solved_leaves == 0
    @test stats.avg_branching_factor == 0.0
    @test isempty(d.branching_factors)
    @test isempty(d.depth_distribution)
    @test d.propagation_calls == 0
    @test d.time_propagation == 0.0
    @test isempty(d.variable_selection_counts)
    @test isempty(d.successful_paths)

    plain_stats = BranchingStats()
@test !BooleanInference.needs_path_tracking(plain_stats)
end