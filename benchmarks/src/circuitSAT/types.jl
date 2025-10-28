struct CircuitSATProblem <: AbstractBenchmarkProblem end

struct CircuitSATConfig <: AbstractProblemConfig
    arithmetic::Bool
end

struct CircuitSATInstance <: AbstractInstance
    filepath::String
    circuit::CircuitSAT
    
    CircuitSATInstance(filepath::String) = new(filepath, read_aag_as_circuitsat(filepath))
end


