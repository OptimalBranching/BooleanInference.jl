module BooleanInference

using TropicalNumbers
using SparseArrays
using OptimalBranchingCore
using OptimalBranchingCore: AbstractProblem, select_variables, reduce_problem, _vec2int, candidate_clauses
using OptimalBranchingCore.BitBasis
using GenericTensorNetworks
using GenericTensorNetworks.OMEinsum
import ProblemReductions
import ProblemReductions: CircuitSAT, Circuit, Factoring, reduceto, Satisfiability
using DataStructures
using DataStructures: PriorityQueue

include("core/types.jl")
include("core/static.jl")
include("core/domain.jl")
include("core/stats.jl")
include("core/workspace.jl")
include("core/region.jl")
include("core/problem.jl")

include("utils/utils.jl")

include("algorithms/knn.jl")
include("algorithms/contraction.jl")
include("algorithms/propagate.jl")

include("branching/measure.jl")
include("branching/selector.jl")
include("branching/branchtable.jl")
include("branching/branch.jl")

include("interface.jl")

export Variable, EdgeRef, BoolTensor, TNStatic, DomainMask, TNProblem
export DM_BOTH, DM_0, DM_1
export Region, RegionCacheEntry, RegionCacheState
export DynamicWorkspace

export is_fixed, has0, has1, init_doms, get_var_value

export setup_problem, setup_from_tensor_network, setup_from_cnf, setup_from_circuit, setup_from_sat

export is_solved, cache_branch_solution!, reset_last_branch_problem!, has_last_branch_problem, last_branch_problem

export solve, solve_sat_problem, solve_sat_with_assignments, solve_factoring
export solve_sat_problem_lookahead, solve_sat_problem_hybrid
export solve_sat_problem_region, solve_sat_problem_region_lookahead

export NumUnfixedVars

export LeastOccurrenceSelector, AbstractSelector
export RegionAwareSelector
export RegionQualityMetrics, evaluate_region_quality, score_region_quality

export TNContractionSolver, AbstractTableSolver

export contract_region, contract_tensors, slicing, tensor_unwrapping

export propagate, get_active_tensors, build_tensor_masks
export TensorMasks, PropagationBuffers
export look_ahead_propagation, look_ahead_score, LookAheadResult

export propagate_incremental, propagate_from_assignment, propagate_from_assignments
export propagate_adaptive, should_use_incremental

export propagate_cdcl, propagate_after_assignment_cdcl, propagate_with_state!
export CDCLPropagationState, Watch, WatchLists, TensorWatchState, TrailEntry

export cache_region!, get_cached_region, clear_all_region_caches!

export k_neighboring, KNNWorkspace

export get_unfixed_vars, count_unfixed, bits_to_int

export get_branching_stats, reset_branching_stats!, print_branching_stats

export BranchingStats, DetailedStats
export record_depth!, record_branch!, record_unsat_leaf!, record_solved_leaf!, record_skipped_subproblem!
export record_propagation!, record_propagation_fixpoint!, record_domain_reduction!, record_early_unsat!
export record_branching_time!, record_contraction_time!, record_cache_hit!, record_cache_miss!
export record_variable_selection!
export print_stats_summary
export get_propagation_efficiency, get_early_unsat_rate, get_cache_hit_rate, get_branching_factor_variance

export extract_inner_configs, combine_configs, slice_region_contraction
export handle_no_boundary_case_unfixed

end
