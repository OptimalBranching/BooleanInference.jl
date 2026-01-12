module BooleanInference

using TropicalNumbers
using SparseArrays
using OptimalBranchingCore
using OptimalBranchingCore: AbstractProblem, select_variables, reduce_problem, _vec2int, candidate_clauses, Clause, BranchingStrategy, AbstractReducer, NoReducer
using OptimalBranchingCore.BitBasis
using GenericTensorNetworks
using GenericTensorNetworks.OMEinsum
import ProblemReductions
import ProblemReductions: CircuitSAT, Circuit, Factoring, reduceto, Satisfiability, Assignment, BooleanExpr, simple_form, extract_symbols!
using Statistics: median, mean, std, var
using Graphs, GraphMakie, Colors
using GraphMakie
using CairoMakie: Figure, Axis, save, hidespines!, hidedecorations!, DataAspect
using NetworkLayout: SFDP, Spring, Stress, Spectral
using Gurobi
using Combinatorics

include("core/static.jl")
include("core/domain.jl")
include("core/stats.jl")
include("core/problem.jl")

include("utils/utils.jl")
include("utils/twosat.jl")
include("utils/circuit2cnf.jl")
include("utils/tn2cnf.jl")
include("utils/simplify_circuit.jl")

include("branching/propagate.jl")
include("branching/measure.jl")

include("branch_table/knn.jl")
include("branch_table/regioncache.jl")
include("branch_table/selector.jl")
include("branch_table/contraction.jl")
include("branch_table/branchtable.jl")

include("branching/reducer.jl")

include("utils/visualization.jl")
include("branching/branch.jl")
include("branching/cubing.jl")
include("core/knuth_estimator.jl")

include("cdcl/KissatSolver.jl")

include("interface.jl")
include("interface_cnc.jl")


export Variable, BoolTensor, ConstraintNetwork, DomainMask, TNProblem, Result
export DomainMask
export Region

# Tensor-based clustering
export TensorRegion, RegionGraph
export init_region_graph, greedy_cluster!, merge_regions!
export compute_merge_gain, compute_open_legs
export get_sorted_regions, region_to_legacy

export is_fixed, has0, has1, init_doms, get_var_value, bits

export setup_problem, setup_from_cnf, setup_from_sat
export factoring_problem, factoring_circuit, factoring_csp

export is_solved

export solve, solve_sat_problem, solve_sat_with_assignments, solve_factoring
export solve_circuit_sat
export FactoringBenchmark, solve_with_benchmark

export NumUnfixedVars

export MostOccurrenceSelector, DPLLSelector, MinGammaSelector, LookaheadSelector, FixedOrderSelector, PropagationAwareSelector

export TNContractionSolver

export contract_region, contract_tensors
export slicing, tensor_unwrapping

export propagate, get_active_tensors

export k_neighboring

export get_unfixed_vars, count_unfixed, bits_to_int
# export compute_circuit_info, map_tensor_to_circuit_info  # Not yet implemented

export get_branching_stats, reset_stats!

export BranchingStats
export print_stats_summary

export to_graph, visualize_problem, visualize_highest_degree_vars
export get_highest_degree_variables, get_tensors_containing_variables

export bbsat!
export BranchingStrategy, NoReducer, GammaOneReducer
export NumHardTensors, NumUnfixedVars, NumUnfixedTensors, HardSetSize, WeightedMeasure, LogEntropyMeasure, NormalizedWeightedMeasure
export TNContractionSolver

export solve_2sat, is_2sat_reducible
export solve_and_mine, solve_cnf, CDCLStats  # Kissat backend
export primal_graph
export circuit_to_cnf, tn_to_cnf, tn_to_cnf_with_doms, num_tn_vars

# Cube-and-Conquer
export AbstractCutoffStrategy, DepthCutoff, VarsCutoff, RatioCutoff, DynamicCutoff, MarchCutoff, CubeLimitCutoff
export Cube, CubeResult, CnCStats, CnCResult
export generate_cubes!, write_cubes_icnf, cubes_to_dimacs
export compute_cube_weights, cube_statistics
export generate_factoring_cubes, generate_cnf_cubes, solve_cubes_with_cdcl, CubesSolveStats
export solve_factoring_cnc

# Knuth tree size estimator
export KnuthEstimatorResult
export knuth_uniform, knuth_importance, compare_measures_knuth
export knuth_estimate, compare_measures, analyze_gamma_distribution  # Aliases
end
