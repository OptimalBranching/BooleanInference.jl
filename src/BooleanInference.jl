module BooleanInference

using JuMP
using HiGHS
using TropicalNumbers
using SparseArrays
using OptimalBranchingCore
using OptimalBranchingCore: AbstractProblem,select_variables,apply_branch,reduce_problem,_vec2int,optimal_branching_rule,candidate_clauses
using OptimalBranchingCore.BitBasis
using GenericTensorNetworks
using GenericTensorNetworks.OMEinsum
import ProblemReductions
import ProblemReductions: CircuitSAT,Circuit,Factoring,reduceto
using KaHyPar

# using GenericTensorNetworks: ∧, ∨, ¬

# status
export BranchingStatus, initialize_branching_status
# stride 
export tensor2vec,get_tensor_number,slice_tensor, vec2tensor,vec2lluint,lluint2vec
# types
export BooleanInferenceProblem,BooleanResultBranchCount,NumOfVertices,NumOfClauses,NumOfDegrees

# interface
export cnf2bip,cir2bip,sat2bip,solvebip,solve_factoring,solve_sat,solve_factoring_count

# reducer
export NoReducer,decide_literal

# selector
export KNeighborSelector,neighboring,k_neighboring,subhg,Smallest2NeighborSelector,KaHyParSelector

# tablesolver
export TNContractionSolver

# readcnf
export readcnf,solvecnf

# tropicalsvd
export tropical_svd

include("status.jl")
include("stride.jl")
include("types.jl")
include("interface.jl")
include("reducer.jl")
include("selector.jl")
include("tablesolver.jl")
include("branch.jl")
include("readcnf.jl")
include("tropicalsvd.jl")
end
