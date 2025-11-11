module CircuitIO
    using ProblemReductions
    using ProblemReductions: Circuit, BooleanExpr, Assignment, extract_symbols!, simple_form, @circuit
    using ProblemReductions: ∧, ∨, ¬, ⊻
    
    include("aig.jl")
    include("verilog.jl")

    export read_aag, aig_to_circuit

    export verilog_to_circuit, parse_verilog_to_circuit
    export write_verilog, circuit_to_verilog

end