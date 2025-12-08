# Solver implementations for CircuitSAT

function solve_instance(::Type{CircuitSATProblem}, instance::CircuitSATInstance, solver::BooleanInferenceSolver)
    try
        result = BooleanInference.solve_circuit_sat(instance.circuit; bsconfig=solver.bsconfig, reducer=solver.reducer, show_stats=solver.show_stats)
        return result
    catch e
        @warn "Failed to solve $(instance.name)" exception=(e, catch_backtrace())
        return nothing
    end
end

# Note: CNFSolver implementation would require additional dependencies
# Keeping it here for future extension
# function solve_instance(::Type{CircuitSATProblem}, instance::CircuitSATInstance, solver::CNFSolver)
#     mktempdir() do dir
#         vfile = joinpath(dir, "circuit.v")
#         aig   = joinpath(dir, "circuit.aig")
#     
#         run(`$(solver.yosys_path) -q -p "read_verilog $vfile; prep -top circuit; aigmap; write_aiger -symbols $aig"`)
#     end
# end