struct CircuitSATProblem <: AbstractBenchmarkProblem end

"""
Configuration for CircuitSAT problems.
- format: :verilog or :aag
- path: path to the circuit file
"""
struct CircuitSATConfig <: AbstractProblemConfig
    format::Symbol  # :verilog or :aag
    path::String
    
    function CircuitSATConfig(format::Symbol, path::String)
        format in (:verilog, :aag) || error("Format must be :verilog or :aag, got $format")
        new(format, path)
    end
end

struct CircuitSATInstance <: AbstractInstance
    name::String
    circuit::Circuit
    format::Symbol
    source_path::String
end
