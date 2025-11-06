module CircuitIO
    using ProblemReductions
    using ProblemReductions: Circuit, BooleanExpr, extract_symbols!, simple_form  

    include("aig.jl")
    include("verilog.jl")

    export aig_to_circuit

    export write_verilog, circuit_to_verilog

end