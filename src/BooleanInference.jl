module BooleanInference

using TropicalNumbers
using SparseArrays
using OptimalBranchingCore
using OptimalBranchingCore: AbstractProblem, select_variables, reduce_problem, _vec2int, candidate_clauses, Clause, BranchingStrategy, AbstractReducer, NoReducer
using OptimalBranchingCore.BitBasis
using GenericTensorNetworks
using GenericTensorNetworks.OMEinsum
import ProblemReductions
import ProblemReductions: CircuitSAT, Circuit, Factoring, reduceto, Satisfiability
using DataStructures
using DataStructures: PriorityQueue
using Statistics: median
using Graphs, GraphMakie, Colors
using GraphMakie
using CairoMakie: Figure, Axis, save, hidespines!, hidedecorations!, DataAspect
using NetworkLayout: SFDP, Spring, Stress, Spectral
import ProblemReductions: BooleanExpr, simple_form, extract_symbols!
using Gurobi

include("core/types.jl")
include("core/static.jl")
include("core/domain.jl")
include("core/stats.jl")
include("core/problem.jl")
include("core/region.jl")

include("utils/utils.jl")
include("utils/circuit_analysis.jl")
include("utils/twosat.jl")

include("branching/propagate.jl")
include("branching/measure.jl")

include("branch_table/knn.jl")
include("branch_table/regioncache.jl")
include("branch_table/selector.jl")
include("branch_table/contraction.jl")
include("branch_table/branchtable.jl")

include("utils/visualization.jl")
include("branching/branch.jl")

include("interface.jl")


export Variable, EdgeRef, BoolTensor, BipartiteGraph, DomainMask, TNProblem, Result
export DM_BOTH, DM_0, DM_1, DM_NONE
export Region

export is_fixed, has0, has1, init_doms, get_var_value, bits

export setup_problem, setup_from_tensor_network, setup_from_cnf, setup_from_circuit, setup_from_sat
export factoring_problem, factoring_circuit, factoring_csp

export is_solved

export solve, solve_sat_problem, solve_sat_with_assignments, solve_factoring
export solve_circuit_sat

export NumUnfixedVars

export MostOccurrenceSelector, LeastOccurrenceSelector, MinGammaSelector, LocalTensorSelector, AbstractSelector

export TNContractionSolver, SingleTensorSolver, AbstractTableSolver, NewTNContractionSolver
export partition_tensor_variables

export contract_region, contract_tensors, slicing, tensor_unwrapping

export propagate, get_active_tensors, build_tensor_masks
export TensorMasks

export cache_region!, get_cached_region, clear_all_region_caches!

export k_neighboring

export get_unfixed_vars, count_unfixed, bits_to_int
export circuit_output_distances
export compute_circuit_info, map_tensor_to_circuit_info

export get_branching_stats, reset_problem!, print_branching_stats

export BranchingStats
export print_stats_summary

export extract_inner_configs, combine_configs, slice_region_contraction
export handle_no_boundary_case_unfixed

export to_graph, visualize_problem, visualize_highest_degree_vars
export get_highest_degree_variables, get_tensors_containing_variables

export branching_table!, branch_and_reduce!, bbsat!
export BranchingStrategy, AbstractReducer, NoReducer
export NumHardTensors, NumUnfixedVars, NumUnfixedTensors, HardSetSize
export TNContractionSolver

export solve_2sat, is_2sat_reducible
end
