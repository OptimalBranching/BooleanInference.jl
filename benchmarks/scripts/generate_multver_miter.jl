#!/usr/bin/env julia

"""
Generate Multiplier Verification Miter circuits.

A miter circuit checks if two implementations produce different outputs.
For multiplier verification:
- Build two multipliers with same inputs
- Check if outputs ever differ (XOR outputs and OR together)
- SAT = implementations differ (bug found)
- UNSAT = implementations equivalent

We create interesting benchmarks by:
1. Comparing correct multiplier vs slightly different (buggy) one
2. Or comparing different multiplier architectures
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using ProblemReductions
using BooleanInference
using Printf

# Global counter for unique symbols
const SYMBOL_COUNTER = Ref(0)
function gensym(prefix::String)
    SYMBOL_COUNTER[] += 1
    Symbol("$(prefix)_$(SYMBOL_COUNTER[])")
end

function reset_symbols!()
    SYMBOL_COUNTER[] = 0
end

"""
Build a half adder: sum = a ⊻ b, carry = a ∧ b
"""
function half_adder!(assignments::Vector{Assignment}, a::Symbol, b::Symbol, prefix::String)
    sum_sym = gensym("$(prefix)_sum")
    carry_sym = gensym("$(prefix)_carry")

    a_expr = BooleanExpr(a)
    b_expr = BooleanExpr(b)

    push!(assignments, Assignment([sum_sym], a_expr ⊻ b_expr))
    push!(assignments, Assignment([carry_sym], a_expr ∧ b_expr))

    return sum_sym, carry_sym
end

"""
Build a full adder: sum = a ⊻ b ⊻ cin, cout = (a ∧ b) ∨ (cin ∧ (a ⊻ b))
"""
function full_adder!(assignments::Vector{Assignment}, a::Symbol, b::Symbol, cin::Symbol, prefix::String)
    xor_ab = gensym("$(prefix)_xab")
    and_ab = gensym("$(prefix)_aab")
    and_xc = gensym("$(prefix)_axc")
    sum_sym = gensym("$(prefix)_sum")
    cout_sym = gensym("$(prefix)_cout")

    a_expr = BooleanExpr(a)
    b_expr = BooleanExpr(b)
    cin_expr = BooleanExpr(cin)

    push!(assignments, Assignment([xor_ab], a_expr ⊻ b_expr))
    push!(assignments, Assignment([and_ab], a_expr ∧ b_expr))
    push!(assignments, Assignment([and_xc], BooleanExpr(xor_ab) ∧ cin_expr))
    push!(assignments, Assignment([sum_sym], BooleanExpr(xor_ab) ⊻ cin_expr))
    push!(assignments, Assignment([cout_sym], BooleanExpr(and_ab) ∨ BooleanExpr(and_xc)))

    return sum_sym, cout_sym
end

"""
Build an n×m array multiplier.
Returns product bits P[1:n+m] (P[1] is LSB).
"""
function build_array_multiplier!(assignments::Vector{Assignment}, A::Vector{Symbol}, B::Vector{Symbol}, prefix::String)
    n = length(A)
    m = length(B)

    # Partial products: pp[i,j] = a_i AND b_j
    PP = Matrix{Symbol}(undef, n, m)
    for i in 1:n
        for j in 1:m
            pp_sym = gensym("$(prefix)_pp_$(i)_$(j)")
            PP[i,j] = pp_sym
            push!(assignments, Assignment([pp_sym], BooleanExpr(A[i]) ∧ BooleanExpr(B[j])))
        end
    end

    # Initialize product bits
    P = Vector{Symbol}(undef, n + m)

    # Create zero constant
    zero_sym = gensym("$(prefix)_zero")
    push!(assignments, Assignment([zero_sym], BooleanExpr(false)))

    # Process using carry-save reduction
    carries = Symbol[]

    for col in 1:(n+m)
        bits = Symbol[]

        # Partial products for this column: i + j - 1 = col
        for i in 1:n
            j = col - i + 1
            if 1 <= j <= m
                push!(bits, PP[i,j])
            end
        end

        # Add carries from previous column
        append!(bits, carries)
        carries = Symbol[]

        if isempty(bits)
            P[col] = zero_sym
            continue
        end

        # Reduce bits to single bit + carries
        adder_idx = 1
        while length(bits) > 1
            new_bits = Symbol[]
            i = 1

            while i <= length(bits)
                if i + 2 <= length(bits)
                    # Full adder
                    sum_sym, cout_sym = full_adder!(assignments, bits[i], bits[i+1], bits[i+2], "$(prefix)_c$(col)_fa$(adder_idx)")
                    push!(new_bits, sum_sym)
                    push!(carries, cout_sym)
                    i += 3
                    adder_idx += 1
                elseif i + 1 <= length(bits)
                    # Half adder
                    sum_sym, cout_sym = half_adder!(assignments, bits[i], bits[i+1], "$(prefix)_c$(col)_ha$(adder_idx)")
                    push!(new_bits, sum_sym)
                    push!(carries, cout_sym)
                    i += 2
                    adder_idx += 1
                else
                    push!(new_bits, bits[i])
                    i += 1
                end
            end
            bits = new_bits
        end

        P[col] = bits[1]
    end

    return P
end

"""
Build a "buggy" multiplier with a small error.
Bug types:
- :stuck_zero: One partial product is stuck at 0
- :stuck_one: One partial product is stuck at 1
- :wrong_and: Use OR instead of AND for one partial product
- :missing_carry: One carry is always 0
"""
function build_buggy_multiplier!(assignments::Vector{Assignment}, A::Vector{Symbol}, B::Vector{Symbol}, prefix::String, bug_type::Symbol, bug_pos::Tuple{Int,Int})
    n = length(A)
    m = length(B)
    bi, bj = bug_pos

    # Partial products with possible bug
    PP = Matrix{Symbol}(undef, n, m)
    for i in 1:n
        for j in 1:m
            pp_sym = gensym("$(prefix)_pp_$(i)_$(j)")
            PP[i,j] = pp_sym

            if (i, j) == (bi, bj)
                # Introduce bug
                if bug_type == :stuck_zero
                    push!(assignments, Assignment([pp_sym], BooleanExpr(false)))
                elseif bug_type == :stuck_one
                    push!(assignments, Assignment([pp_sym], BooleanExpr(true)))
                elseif bug_type == :wrong_or
                    push!(assignments, Assignment([pp_sym], BooleanExpr(A[i]) ∨ BooleanExpr(B[j])))
                elseif bug_type == :wrong_xor
                    push!(assignments, Assignment([pp_sym], BooleanExpr(A[i]) ⊻ BooleanExpr(B[j])))
                else
                    push!(assignments, Assignment([pp_sym], BooleanExpr(A[i]) ∧ BooleanExpr(B[j])))
                end
            else
                push!(assignments, Assignment([pp_sym], BooleanExpr(A[i]) ∧ BooleanExpr(B[j])))
            end
        end
    end

    # Same reduction logic as correct multiplier
    P = Vector{Symbol}(undef, n + m)
    zero_sym = gensym("$(prefix)_zero")
    push!(assignments, Assignment([zero_sym], BooleanExpr(false)))

    carries = Symbol[]

    for col in 1:(n+m)
        bits = Symbol[]

        for i in 1:n
            j = col - i + 1
            if 1 <= j <= m
                push!(bits, PP[i,j])
            end
        end

        append!(bits, carries)
        carries = Symbol[]

        if isempty(bits)
            P[col] = zero_sym
            continue
        end

        adder_idx = 1
        while length(bits) > 1
            new_bits = Symbol[]
            i = 1

            while i <= length(bits)
                if i + 2 <= length(bits)
                    sum_sym, cout_sym = full_adder!(assignments, bits[i], bits[i+1], bits[i+2], "$(prefix)_c$(col)_fa$(adder_idx)")
                    push!(new_bits, sum_sym)
                    push!(carries, cout_sym)
                    i += 3
                    adder_idx += 1
                elseif i + 1 <= length(bits)
                    sum_sym, cout_sym = half_adder!(assignments, bits[i], bits[i+1], "$(prefix)_c$(col)_ha$(adder_idx)")
                    push!(new_bits, sum_sym)
                    push!(carries, cout_sym)
                    i += 2
                    adder_idx += 1
                else
                    push!(new_bits, bits[i])
                    i += 1
                end
            end
            bits = new_bits
        end

        P[col] = bits[1]
    end

    return P
end

"""
Build a miter circuit comparing two multipliers.
Output is SAT iff the two multipliers produce different results for some input.
"""
function build_multiplier_miter(n::Int, m::Int; buggy::Bool=true, bug_type::Symbol=:stuck_zero, bug_pos::Tuple{Int,Int}=(1,1))
    reset_symbols!()
    assignments = Assignment[]

    # Shared inputs
    A = [Symbol("a$i") for i in 1:n]
    B = [Symbol("b$j") for j in 1:m]

    # Build correct multiplier
    P_correct = build_array_multiplier!(assignments, A, B, "correct")

    # Build second multiplier (buggy or correct)
    if buggy
        P_test = build_buggy_multiplier!(assignments, A, B, "buggy", bug_type, bug_pos)
    else
        # Build identical multiplier (should be UNSAT)
        P_test = build_array_multiplier!(assignments, A, B, "test")
    end

    # Miter: XOR corresponding outputs and OR all together
    xor_syms = Symbol[]
    for k in 1:(n+m)
        xor_sym = gensym("miter_xor_$(k)")
        push!(assignments, Assignment([xor_sym], BooleanExpr(P_correct[k]) ⊻ BooleanExpr(P_test[k])))
        push!(xor_syms, xor_sym)
    end

    # OR all XORs together - if any bit differs, miter is SAT
    if length(xor_syms) == 1
        miter_out = xor_syms[1]
    else
        # Build OR tree
        or_result = xor_syms[1]
        for k in 2:length(xor_syms)
            new_or = gensym("miter_or_$(k)")
            push!(assignments, Assignment([new_or], BooleanExpr(or_result) ∨ BooleanExpr(xor_syms[k])))
            or_result = new_or
        end
        miter_out = or_result
    end

    # miter_out is the final OR of all XORs
    # We need to force miter_out = TRUE for SAT (meaning outputs differ)
    # Return miter_out symbol so we can add unit clause in CNF

    circuit = Circuit(assignments)
    return circuit, A, B, miter_out
end

function save_miter_cnf(n::Int, m::Int, output_dir::String; buggy::Bool=true, bug_type::Symbol=:stuck_zero, bug_pos::Tuple{Int,Int}=(1,1))
    bug_str = buggy ? "$(bug_type)_$(bug_pos[1])_$(bug_pos[2])" : "equiv"

    println("Building $(n)×$(m) multiplier miter ($(bug_str))...")

    circuit, A, B, miter_out = build_multiplier_miter(n, m; buggy=buggy, bug_type=bug_type, bug_pos=bug_pos)

    ngates = length(circuit.exprs)
    println("  Gates: $ngates")

    cnf, symbols = circuit_to_cnf(circuit)

    # Find the index of miter_out symbol and add unit clause to force it TRUE
    miter_idx = findfirst(==(miter_out), symbols)
    if !isnothing(miter_idx)
        push!(cnf, [miter_idx])  # Unit clause forcing miter_out = TRUE
    else
        @warn "Could not find miter_out symbol: $miter_out"
    end

    nvars = length(symbols)
    nclauses = length(cnf)

    println("  Variables: $nvars")
    println("  CNF Clauses: $nclauses")

    filename = buggy ? "miter_$(n)x$(m)_$(bug_str).cnf" : "miter_$(n)x$(m)_equiv.cnf"
    filepath = joinpath(output_dir, filename)

    open(filepath, "w") do io
        println(io, "c Multiplier Miter: $(n)x$(m)")
        println(io, "c Bug: $(bug_str)")
        println(io, "c SAT = multipliers differ, UNSAT = equivalent")
        println(io, "c Gates: $ngates")
        println(io, "p cnf $nvars $nclauses")

        for clause in cnf
            for lit in clause
                print(io, lit, " ")
            end
            println(io, "0")
        end
    end

    println("  Saved: $filepath")
    return nvars, ngates, nclauses, filename
end

function main()
    output_dir = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "..", "data", "multver")
    mkpath(output_dir)

    println("=" ^ 70)
    println("Generating Multiplier Verification Miter Circuits")
    println("=" ^ 70)
    println()
    println("These are proper verification benchmarks:")
    println("- SAT = bug found (multipliers produce different output)")
    println("- UNSAT = multipliers are equivalent")
    println()

    stats = []

    # Generate buggy miters (should be SAT)
    sizes = [(4, 4), (6, 6), (8, 8), (10, 10), (12, 12)]
    bug_types = [:stuck_zero, :stuck_one, :wrong_xor]

    for (n, m) in sizes
        for bug_type in bug_types
            # Bug at middle position
            bug_pos = (n÷2, m÷2)
            println("-" ^ 70)
            nvars, ngates, nclauses, filename = save_miter_cnf(n, m, output_dir;
                buggy=true, bug_type=bug_type, bug_pos=bug_pos)
            push!(stats, (n, m, "$(bug_type)", nvars, ngates, nclauses, "SAT"))
            println()
        end
    end

    # Generate equivalence check (should be UNSAT - harder!)
    for (n, m) in sizes
        println("-" ^ 70)
        nvars, ngates, nclauses, filename = save_miter_cnf(n, m, output_dir; buggy=false)
        push!(stats, (n, m, "equiv", nvars, ngates, nclauses, "UNSAT"))
        println()
    end

    println("=" ^ 70)
    println("Summary:")
    println(@sprintf("%-8s %-12s %8s %8s %10s %8s", "Size", "Bug", "Vars", "Gates", "Clauses", "Expected"))
    println("-" ^ 70)
    for (n, m, bug, nvars, ngates, nclauses, expected) in stats
        println(@sprintf("%dx%-5d %-12s %8d %8d %10d %8s", n, m, bug, nvars, ngates, nclauses, expected))
    end

    println()
    println("To test with march:")
    println("  ./march_cu miter_8x8_stuck_zero_4_4.cnf -p   # Should be SAT")
    println("  ./march_cu miter_8x8_equiv.cnf -p            # Should be UNSAT")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
