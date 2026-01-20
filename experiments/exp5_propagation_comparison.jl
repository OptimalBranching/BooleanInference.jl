"""
Experiment 5: Propagation Power Comparison - TN vs CNF

Compare the propagation power of the same circuit in:
1. TN (Tensor Network) form: Using constraint propagation through tensor supports
2. CNF (Tseitin encoding): Using unit propagation on Tseitin-transformed CNF

For the same variable assignment, measure how many additional variables
are determined by propagation in each representation.

Note: We use Tseitin CNF encoding (from circuit_to_cnf) which has stronger
propagation than blocking-clause encoding (from tn_to_cnf).
"""

include("exp1_utils.jl")

using BooleanInference
using BooleanInference: DomainMask, DM_NONE, DM_0, DM_1, DM_BOTH, is_fixed
using BooleanInference: probe_assignment_core!, propagate!, num_tn_vars, init_doms
using BooleanInference: circuit_to_cnf, tn_to_cnf
using ProblemReductions: reduceto, CircuitSAT, Factoring, constraints
using Random: randperm

# ============================================================================
# CNF Unit Propagation Implementation
# ============================================================================

"""
    UnitPropResult

Result of unit propagation on CNF.
"""
struct UnitPropResult
    assignments::Vector{Int8}  # 0: unassigned, 1: true, -1: false
    n_propagated::Int          # Number of variables fixed by propagation
    contradiction::Bool        # Whether a contradiction was found
end

"""
    unit_propagate_fresh(cnf, nvars_original, new_assignments) -> UnitPropResult

Perform unit propagation on CNF.
1. First propagates existing unit clauses to establish baseline
2. Then applies new_assignments and propagates further
3. Returns count of variables propagated due to new_assignments only

Arguments:
- cnf: Vector of clauses (may contain unit clauses)
- nvars_original: Number of original variables (for counting)
- new_assignments: Dict{Int, Bool} - the NEW assignments to test

Returns UnitPropResult with propagation count (excluding baseline).
"""
function unit_propagate_fresh(cnf::Vector{Vector{Int}}, nvars_original::Int, new_assignments::Dict{Int,Bool})
    # Find max variable
    max_var = nvars_original
    for clause in cnf
        for lit in clause
            max_var = max(max_var, abs(lit))
        end
    end

    # Create watch lists
    watch_pos = [Int[] for _ in 1:max_var]
    watch_neg = [Int[] for _ in 1:max_var]
    for (clause_idx, clause) in enumerate(cnf)
        for lit in clause
            var = abs(lit)
            if lit > 0
                push!(watch_pos[var], clause_idx)
            else
                push!(watch_neg[var], clause_idx)
            end
        end
    end

    # Phase 1: Propagate existing unit clauses (baseline)
    assignments = zeros(Int8, max_var)
    queue = Int[]

    for clause in cnf
        if length(clause) == 1
            lit = clause[1]
            var = abs(lit)
            if assignments[var] == 0
                assignments[var] = lit > 0 ? Int8(1) : Int8(-1)
                push!(queue, var)
            end
        end
    end

    # Run baseline propagation
    result = run_propagation!(assignments, cnf, queue, watch_pos, watch_neg)
    if result === nothing
        return UnitPropResult(zeros(Int8, nvars_original), 0, true)
    end
    n_baseline = count(assignments[i] != 0 for i in 1:nvars_original)

    # Phase 2: Apply new assignments
    n_direct = 0
    for (var, val) in new_assignments
        if var <= max_var
            new_val = val ? Int8(1) : Int8(-1)
            if assignments[var] == 0
                assignments[var] = new_val
                push!(queue, var)
                n_direct += 1
            elseif assignments[var] != new_val
                # Contradiction with baseline
                return UnitPropResult(assignments[1:nvars_original], 0, true)
            end
        end
    end

    # Run propagation for new assignments
    result = run_propagation!(assignments, cnf, queue, watch_pos, watch_neg)
    if result === nothing
        n_propagated = count(assignments[i] != 0 for i in 1:nvars_original) - n_baseline - n_direct
        return UnitPropResult(assignments[1:nvars_original], max(0, n_propagated), true)
    end

    n_final = count(assignments[i] != 0 for i in 1:nvars_original)
    n_propagated = n_final - n_baseline - n_direct
    return UnitPropResult(assignments[1:nvars_original], max(0, n_propagated), false)
end

"""
Helper: Run unit propagation until fixpoint.
Returns assignments or nothing if contradiction.
"""
function run_propagation!(assignments::Vector{Int8}, cnf::Vector{Vector{Int}},
                          queue::Vector{Int}, watch_pos, watch_neg)
    while !isempty(queue)
        var = popfirst!(queue)
        val = assignments[var]
        false_lit_clauses = val == 1 ? watch_neg[var] : watch_pos[var]

        for clause_idx in false_lit_clauses
            clause = cnf[clause_idx]
            n_unassigned = 0
            unassigned_lit = 0
            is_satisfied = false

            for lit in clause
                lit_var = abs(lit)
                lit_val = assignments[lit_var]
                if lit_val == 0
                    n_unassigned += 1
                    unassigned_lit = lit
                elseif (lit > 0 && lit_val == 1) || (lit < 0 && lit_val == -1)
                    is_satisfied = true
                    break
                end
            end

            is_satisfied && continue

            if n_unassigned == 0
                return nothing  # Contradiction
            elseif n_unassigned == 1
                unit_var = abs(unassigned_lit)
                if assignments[unit_var] == 0
                    assignments[unit_var] = unassigned_lit > 0 ? Int8(1) : Int8(-1)
                    push!(queue, unit_var)
                end
            end
        end
    end
    return assignments
end

# ============================================================================
# Propagation Comparison Functions
# ============================================================================

"""
    PropagationComparison

Result of comparing TN and CNF propagation for a single assignment.
"""
struct PropagationComparison
    instance_name::String
    assignment_size::Int       # Number of initially assigned variables

    # TN results
    tn_propagated::Int         # Variables fixed by TN propagation
    tn_total_fixed::Int        # Total fixed after propagation
    tn_contradiction::Bool
    tn_time::Float64

    # Tseitin CNF results
    cnf_propagated::Int        # Variables fixed by CNF unit propagation
    cnf_total_fixed::Int       # Total fixed after propagation
    cnf_contradiction::Bool
    cnf_time::Float64

    # Comparison
    propagation_diff::Int      # tn_propagated - cnf_propagated (positive = TN stronger)
end

"""
    compare_propagation_tseitin(tn_problem, base_doms, tseitin_cnf, tn_to_cnf_var, vars_to_assign, values, instance_name)

Compare propagation power of TN vs Tseitin CNF for a given partial assignment.
Uses base_doms as the starting state (should be unpropagated for fair comparison).
"""
function compare_propagation_tseitin(
    tn_problem::TNProblem,
    base_doms::Vector{DomainMask},
    tseitin_cnf::Vector{Vector{Int}},
    tn_to_cnf_var::Dict{Int,Int},
    vars_to_assign::Vector{Int},
    values::Vector{Bool},
    instance_name::String=""
)
    nvars_tn = num_tn_vars(tn_problem.static)
    n_assign = length(vars_to_assign)

    # Count initially unfixed variables (should be all for fresh doms)
    initial_unfixed_tn = count(base_doms[i] == DM_BOTH for i in 1:nvars_tn)

    # ========== TN Propagation ==========
    tn_time = @elapsed begin
        mask = UInt64(0)
        value = UInt64(0)
        for (i, v) in enumerate(values)
            mask |= UInt64(1) << (i - 1)
            if v
                value |= UInt64(1) << (i - 1)
            end
        end

        result_doms = probe_assignment_core!(
            tn_problem, tn_problem.buffer,
            copy(base_doms), vars_to_assign, mask, value
        )
    end

    tn_contradiction = result_doms[1] == DM_NONE
    tn_unfixed_after = tn_contradiction ? 0 : count(result_doms[i] == DM_BOTH for i in 1:nvars_tn)
    tn_propagated = initial_unfixed_tn - tn_unfixed_after - n_assign
    tn_total_fixed = nvars_tn - tn_unfixed_after

    # ========== Tseitin CNF Unit Propagation ==========
    # Map TN variables to CNF variables
    cnf_assignments = Dict{Int,Bool}()
    for (i, tn_var) in enumerate(vars_to_assign)
        if haskey(tn_to_cnf_var, tn_var)
            cnf_var = tn_to_cnf_var[tn_var]
            cnf_assignments[cnf_var] = values[i]
        end
    end

    nvars_cnf = length(tn_to_cnf_var)  # Only count mapped variables

    cnf_time = @elapsed begin
        cnf_result = unit_propagate_fresh(tseitin_cnf, nvars_cnf, cnf_assignments)
    end

    cnf_propagated = cnf_result.n_propagated
    cnf_total_fixed = count(cnf_result.assignments[i] != 0 for i in 1:min(nvars_cnf, length(cnf_result.assignments)))
    cnf_contradiction = cnf_result.contradiction

    return PropagationComparison(
        instance_name,
        n_assign,
        tn_propagated,
        tn_total_fixed,
        tn_contradiction,
        tn_time,
        cnf_propagated,
        cnf_total_fixed,
        cnf_contradiction,
        cnf_time,
        tn_propagated - cnf_propagated
    )
end

"""
    select_random_unfixed_vars(doms, n_select) -> (vars, values)

Select n_select random unfixed variables and random values for them.
"""
function select_random_unfixed_vars(doms::Vector{DomainMask}, n_select::Int)
    unfixed = findall(dm -> dm == DM_BOTH, doms)
    n_select = min(n_select, length(unfixed))

    selected = sort(unfixed[randperm(length(unfixed))[1:n_select]])
    values = rand(Bool, n_select)

    return selected, values
end

"""
    create_variable_mapping(circuit_sat_symbols, tn_symbols)

Create mapping from TN variable indices to CNF variable indices.
Both use 1-based indexing based on symbol order.
"""
function create_variable_mapping(circuit_sat_symbols::Vector{Symbol}, tn_symbols::Vector{Symbol})
    # Create symbol -> CNF var mapping
    cnf_sym_to_var = Dict{Symbol, Int}(s => i for (i, s) in enumerate(circuit_sat_symbols))

    # Create TN var -> CNF var mapping
    tn_to_cnf = Dict{Int, Int}()
    for (tn_var, sym) in enumerate(tn_symbols)
        if haskey(cnf_sym_to_var, sym)
            tn_to_cnf[tn_var] = cnf_sym_to_var[sym]
        end
    end

    return tn_to_cnf
end

# ============================================================================
# Main Experiment
# ============================================================================

"""
    run_exp5(; kwargs...)

Run propagation comparison experiment.
"""
function run_exp5(;
    max_instances::Int=5,
    output_dir::String="results",
    bit_sizes::Vector{Int}=[8, 10],
    n_samples_per_instance::Int=20,
    assignment_sizes::Vector{Int}=[1, 3, 5, 10]
)
    println("\n" * "="^80)
    println("Experiment 5: TN vs Tseitin CNF Propagation Power Comparison")
    println("="^80)

    metadata = get_experiment_metadata(
        "exp5_propagation_comparison",
        description="Compare propagation power between TN and Tseitin CNF representations"
    )
    metadata["parameters"] = Dict{String,Any}(
        "bit_sizes" => bit_sizes,
        "max_instances" => max_instances,
        "n_samples_per_instance" => n_samples_per_instance,
        "assignment_sizes" => assignment_sizes
    )

    data_dir = joinpath(dirname(@__DIR__), "benchmarks", "data", "factoring")
    all_results = PropagationComparison[]

    for bit_size in bit_sizes
        data_file = joinpath(data_dir, "numbers_$(bit_size)x$(bit_size).txt")
        if !isfile(data_file)
            @warn "Data file not found: $data_file"
            continue
        end

        instances = load_factoring_instances(data_file; max_instances=max_instances)
        println("\n[$(bit_size)x$(bit_size)] Loaded $(length(instances)) instances")

        for (idx, inst) in enumerate(instances)
            println("\n  [$(idx)/$(length(instances))] N=$(inst.N)")

            # Create circuit and both representations
            print("    Creating circuit... ")
            reduction = reduceto(CircuitSAT, Factoring(inst.n, inst.m, inst.N))
            circuit = reduction.circuit.circuit
            circuit_sat = CircuitSAT(circuit; use_constraints=true)
            println("done")

            # Create TN problem
            print("    Creating TN problem... ")
            tn_problem = setup_from_sat(circuit_sat)
            nvars_tn = num_tn_vars(tn_problem.static)
            tn_symbols = circuit_sat.symbols
            # 使用初始化后的 doms（已传播约束），与 CNF baseline 公平比较
            # TN 的 tn_problem.doms 会传播约束（如 output=1），CNF 的 baseline 也会
            base_doms = copy(tn_problem.doms)
            n_initially_fixed = count(is_fixed(base_doms[i]) for i in 1:nvars_tn)
            println("done ($(nvars_tn) vars, $(n_initially_fixed) initially fixed)")

            # Create Tseitin CNF (same as march_cu uses)
            print("    Creating Tseitin CNF... ")
            tseitin_cnf, cnf_symbols = circuit_to_cnf(circuit; simplify=false)

            # Add unary constraints from CircuitSAT (output=1, etc.)
            sym_to_var = Dict{Symbol,Int}(s => i for (i, s) in enumerate(cnf_symbols))
            for constraint in constraints(circuit_sat)
                if length(constraint.variables) == 1
                    var_idx = constraint.variables[1]
                    sym = tn_symbols[var_idx]
                    if haskey(sym_to_var, sym)
                        cnf_var = sym_to_var[sym]
                        spec = constraint.specification
                        if spec == [false, true]
                            push!(tseitin_cnf, [cnf_var])
                        elseif spec == [true, false]
                            push!(tseitin_cnf, [-cnf_var])
                        end
                    end
                end
            end
            println("done ($(length(tseitin_cnf)) clauses, $(length(cnf_symbols)) vars)")

            # Create variable mapping
            tn_to_cnf_var = create_variable_mapping(cnf_symbols, tn_symbols)
            println("    Variable mapping: $(length(tn_to_cnf_var)) vars mapped")

            # Count unfixed variables (all should be unfixed in base_doms)
            n_unfixed = count(base_doms[i] == DM_BOTH for i in 1:nvars_tn)
            println("    Unfixed variables: $(n_unfixed)")

            if n_unfixed == 0
                println("    ⚠ No unfixed variables, skipping")
                continue
            end

            # Run samples for each assignment size
            for assign_size in assignment_sizes
                if assign_size > n_unfixed
                    continue
                end

                print("    Assignment size=$assign_size: ")

                instance_results = PropagationComparison[]
                for _ in 1:n_samples_per_instance
                    vars, values = select_random_unfixed_vars(base_doms, assign_size)
                    result = compare_propagation_tseitin(
                        tn_problem, base_doms, tseitin_cnf, tn_to_cnf_var,
                        vars, values,
                        "$(inst.n)x$(inst.m)_$(inst.N)"
                    )
                    push!(instance_results, result)
                end

                # Compute statistics
                avg_tn = mean(r.tn_propagated for r in instance_results)
                avg_cnf = mean(r.cnf_propagated for r in instance_results)
                avg_diff = mean(r.propagation_diff for r in instance_results)

                @printf("TN=%.1f, CNF=%.1f, diff=%.1f\n", avg_tn, avg_cnf, avg_diff)

                append!(all_results, instance_results)
            end
        end
    end

    # Save results
    output_path = get_output_path(output_dir, "exp5_propagation_comparison")
    save_propagation_results(all_results, output_path; metadata=metadata)

    # Print summary
    print_propagation_summary(all_results, assignment_sizes)

    return all_results
end

"""
    save_propagation_results(results, filepath; metadata)

Save propagation comparison results to CSV and JSON.
"""
function save_propagation_results(
    results::Vector{PropagationComparison},
    filepath::String;
    metadata::Dict{String,Any}=Dict{String,Any}()
)
    # Save as CSV
    df = DataFrame(
        instance = [r.instance_name for r in results],
        assignment_size = [r.assignment_size for r in results],
        tn_propagated = [r.tn_propagated for r in results],
        tn_total_fixed = [r.tn_total_fixed for r in results],
        tn_contradiction = [r.tn_contradiction for r in results],
        tn_time = [r.tn_time for r in results],
        cnf_propagated = [r.cnf_propagated for r in results],
        cnf_total_fixed = [r.cnf_total_fixed for r in results],
        cnf_contradiction = [r.cnf_contradiction for r in results],
        cnf_time = [r.cnf_time for r in results],
        propagation_diff = [r.propagation_diff for r in results]
    )
    CSV.write(filepath * ".csv", df)

    # Save as JSON with metadata
    json_output = Dict{String,Any}(
        "metadata" => metadata,
        "results" => [
            Dict{String,Any}(
                "instance" => r.instance_name,
                "assignment_size" => r.assignment_size,
                "tn_propagated" => r.tn_propagated,
                "tn_total_fixed" => r.tn_total_fixed,
                "tn_contradiction" => r.tn_contradiction,
                "tn_time" => r.tn_time,
                "cnf_propagated" => r.cnf_propagated,
                "cnf_total_fixed" => r.cnf_total_fixed,
                "cnf_contradiction" => r.cnf_contradiction,
                "cnf_time" => r.cnf_time,
                "propagation_diff" => r.propagation_diff
            )
            for r in results
        ]
    )
    open(filepath * ".json", "w") do f
        JSON3.pretty(f, json_output)
    end

    println("\nResults saved to:")
    println("  - $(filepath).csv")
    println("  - $(filepath).json")
end

"""
    print_propagation_summary(results, assignment_sizes)

Print summary table comparing TN and CNF propagation.
"""
function print_propagation_summary(results::Vector{PropagationComparison}, assignment_sizes::Vector{Int})
    println("\n" * "="^80)
    println("Summary: TN vs Tseitin CNF Propagation Power")
    println("="^80)

    df = DataFrame(
        assignment_size = [r.assignment_size for r in results],
        tn_propagated = [r.tn_propagated for r in results],
        cnf_propagated = [r.cnf_propagated for r in results],
        propagation_diff = [r.propagation_diff for r in results],
        tn_time = [r.tn_time for r in results],
        cnf_time = [r.cnf_time for r in results]
    )

    grouped = combine(DataFrames.groupby(df, :assignment_size),
        :tn_propagated => mean => :avg_tn,
        :tn_propagated => std => :std_tn,
        :cnf_propagated => mean => :avg_cnf,
        :cnf_propagated => std => :std_cnf,
        :propagation_diff => mean => :avg_diff,
        :tn_time => mean => :avg_tn_time,
        :cnf_time => mean => :avg_cnf_time,
        nrow => :n_samples
    )

    println("\n")
    @printf("%-12s %12s %12s %12s %12s %10s\n",
        "Assign Size", "TN Prop", "CNF Prop", "Diff (TN-CNF)", "TN Time (ms)", "CNF Time (ms)")
    println("-"^75)

    for row in eachrow(grouped)
        @printf("%-12d %8.1f±%.1f %8.1f±%.1f %12.1f %12.3f %12.3f\n",
            row.assignment_size,
            row.avg_tn, row.std_tn,
            row.avg_cnf, row.std_cnf,
            row.avg_diff,
            row.avg_tn_time * 1000,
            row.avg_cnf_time * 1000
        )
    end
    println("-"^75)

    # Overall statistics
    total_tn = sum(r.tn_propagated for r in results)
    total_cnf = sum(r.cnf_propagated for r in results)
    ratio = total_cnf > 0 ? total_tn / total_cnf : Inf

    println("\nOverall:")
    println("  Total TN propagated: $(total_tn)")
    println("  Total CNF propagated: $(total_cnf)")
    @printf("  TN/CNF ratio: %.2f\n", ratio)

    # Contradiction analysis
    tn_contradictions = count(r.tn_contradiction for r in results)
    cnf_contradictions = count(r.cnf_contradiction for r in results)
    println("\n  Contradictions detected:")
    println("    TN: $(tn_contradictions) / $(length(results))")
    println("    CNF: $(cnf_contradictions) / $(length(results))")

    # Cases where TN is strictly better
    tn_better = count(r.propagation_diff > 0 for r in results)
    cnf_better = count(r.propagation_diff < 0 for r in results)
    equal = count(r.propagation_diff == 0 for r in results)
    println("\n  Comparison (out of $(length(results)) samples):")
    @printf("    TN better: %d (%.1f%%)\n", tn_better, 100 * tn_better / length(results))
    @printf("    CNF better: %d (%.1f%%)\n", cnf_better, 100 * cnf_better / length(results))
    @printf("    Equal: %d (%.1f%%)\n", equal, 100 * equal / length(results))
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    run_exp5(
        max_instances=5,
        output_dir="results",
        bit_sizes=[8, 10],
        n_samples_per_instance=20,
        assignment_sizes=[1, 3, 5, 10]
    )
end
