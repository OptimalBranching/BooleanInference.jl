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

# using GenericTensorNetworks: ∧, ∨, ¬

include("problems.jl")
include("region.jl")
include("measure.jl")
include("utils.jl")
include("knn.jl")
include("selector.jl")
include("contraction.jl")
include("branchtable.jl")
include("branch.jl")
include("propagate.jl")
include("interface.jl")

# Export core types
export Variable, EdgeRef, BoolTensor, TNStatic, DomainMask, TNProblem
export DM_BOTH, DM_0, DM_1
export Region, RegionContraction, RegionCacheEntry, RegionCacheState, RegionCache
export DynamicWorkspace

# Export domain mask functions
export is_fixed, has0, has1, init_doms, get_var_value

# Export problem setup functions
export setup_problem, setup_from_tensor_network, setup_from_cnf, setup_from_circuit, setup_from_sat

# Export problem state functions
export is_solved, cache_branch_solution!, reset_last_branch_problem!, has_last_branch_problem, last_branch_problem

# Export solving functions
export solve, solve_sat_problem, solve_sat_with_assignments, solve_factoring

# Export measure types
export NumUnfixedVars

# Export selector types
export LeastOccurrenceSelector, AbstractSelector

# Export table solver types
export TNContractionSolver, AbstractTableSolver

# Export contraction functions
export contract_region, contract_tensors, slicing, tensor_unwrapping

# Export propagation functions
export propagate, get_active_tensors, build_tensor_masks
export TensorMasks, PropagationBuffers

# Export region management functions
export cache_region!, get_cached_region_entry, get_cached_region, cache_region_contraction!
export get_cached_region_contraction, clear_region_cache!, clear_all_region_caches!

# Export k-neighboring functions
export k_neighboring, KNNWorkspace

# Export utility functions
export get_unfixed_vars, count_unfixed, bits_to_int

# Export branching statistics functions
export get_branching_stats, reset_branching_stats!, print_branching_stats

# Export branching table functions
export separate_fixed_free_boundary, construct_boundary_config, construct_inner_config
export extract_inner_configs, combine_configs, get_region_contraction, slice_region_contraction
export handle_no_boundary_case

end
