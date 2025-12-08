# Types for CNF SAT problem instances

struct CNFSATProblem <: AbstractBenchmarkProblem end

"""
Configuration for CNF SAT problems.
- path: path to the CNF file in DIMACS format
"""
struct CNFSATConfig <: AbstractProblemConfig
    path::String

    function CNFSATConfig(path::String)
        isfile(path) || error("CNF file not found: $path")
        new(path)
    end
end

"""
Represents a CNF SAT instance loaded from a DIMACS file.
Fields:
- name: instance name (typically filename without extension)
- num_vars: number of variables
- num_clauses: number of clauses
- clauses: vector of clauses, where each clause is a vector of literals (integers)
- source_path: path to the original CNF file
"""
struct CNFSATInstance <: AbstractInstance
    name::String
    num_vars::Int
    num_clauses::Int
    clauses::Vector{Vector{Int}}
    source_path::String
end
