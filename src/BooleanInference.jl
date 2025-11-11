module BooleanInference

using TropicalNumbers
using SparseArrays
using OptimalBranchingCore
using OptimalBranchingCore: AbstractProblem, select_variables, reduce_problem, _vec2int, candidate_clauses, Clause
using OptimalBranchingCore.BitBasis
using GenericTensorNetworks
using GenericTensorNetworks.OMEinsum
import ProblemReductions
import ProblemReductions: CircuitSAT, Circuit, Factoring, reduceto, Satisfiability
using DataStructures
using DataStructures: PriorityQueue
using Statistics: median

include("core/types.jl")
include("core/static.jl")
include("core/domain.jl")
include("core/stats.jl")
include("core/workspace.jl")
include("core/region.jl")
include("core/problem.jl")

include("utils/utils.jl")

include("branching/propagate.jl")

include("branching/measure.jl")
include("branching/selector.jl")

include("branch_table/TNContraction/knn.jl")
include("branch_table/TNContraction/contraction.jl")
include("branch_table/TNContraction/branchtable.jl")

include("branch_table/LocalTensor/branchtable.jl")


include("branching/branch_cache.jl")
include("branching/greedymerge.jl")
include("branching/optimal_branching.jl")
include("branching/branch.jl")

include("interface.jl")

export Variable, EdgeRef, BoolTensor, TNStatic, DomainMask, TNProblem
export DM_BOTH, DM_0, DM_1, DM_NONE
export Region, RegionCacheEntry, RegionCacheState
export DynamicWorkspace

export is_fixed, has0, has1, init_doms, get_var_value, bits

export setup_problem, setup_from_tensor_network, setup_from_cnf, setup_from_circuit, setup_from_sat

export is_solved, cache_branch_solution!, reset_last_branch_problem!, has_last_branch_problem, last_branch_problem

export solve, solve_sat_problem, solve_sat_with_assignments, solve_factoring
export solve_circuit_sat

export NumUnfixedVars

export MostOccurrenceSelector, MinGammaSelector, AbstractSelector
export RegionAwareSelector, PropagationAwareSelector

export TNContractionSolver, AbstractTableSolver

export contract_region, contract_tensors, slicing, tensor_unwrapping

export propagate, get_active_tensors, build_tensor_masks
export TensorMasks, PropagationBuffers

export cache_region!, get_cached_region, clear_all_region_caches!

export k_neighboring, KNNWorkspace

export get_unfixed_vars, count_unfixed, bits_to_int
export circuit_output_distances

export get_branching_stats, reset_branching_stats!, print_branching_stats

export BranchingStats, DetailedStats
export record_depth!, record_branch!, record_unsat_leaf!, record_solved_leaf!, record_skipped_subproblem!
export record_propagation!, record_domain_reduction!, record_early_unsat!
export record_branching_time!, record_contraction_time!, record_filtering_time!, record_cache_hit!, record_cache_miss!
export record_variable_selection!
export print_stats_summary
export reset!

export extract_inner_configs, combine_configs, slice_region_contraction
export handle_no_boundary_case_unfixed

end
