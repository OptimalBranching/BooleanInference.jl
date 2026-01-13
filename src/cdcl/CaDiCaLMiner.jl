# -----------------------------
# Shared library path
# -----------------------------
const _libname = Sys.isapple() ? "libcadical_mine.dylib" :
                 Sys.iswindows() ? "libcadical_mine.dll" :
                 "libcadical_mine.so"

# This file is expected at: <pkg>/src/cdcl/CaDiCaLMiner.jl
# The library is expected at: <pkg>/deps/build/<libname>
const lib = normpath(joinpath(@__DIR__, "..", "..", "deps", "cadical", "build", _libname))

# -----------------------------
# CNF flatten/unflatten helpers
# -----------------------------

"""
    flatten_cnf(cnf) -> (lits::Vector{Int32}, offsets::Vector{Int32})

Flatten CNF from `Vector{Vector{Int}}` into:
- `lits`: concatenated literals
- `offsets`: length = nclauses + 1, offsets[i] is starting index (0-based) in `lits`
"""
function flatten_cnf(cnf::Vector{<:AbstractVector{<:Integer}})
    nclauses = length(cnf)
    offsets = Vector{Int32}(undef, nclauses + 1)
    offsets[1] = 0
    total = 0
    @inbounds for i in 1:nclauses
        total += length(cnf[i])
        offsets[i+1] = Int32(total)
    end

    lits = Vector{Int32}(undef, total)
    p = 1
    @inbounds for c in cnf
        for lit in c
            lits[p] = Int32(lit)
            p += 1
        end
    end
    return lits, offsets
end

"""
    unflatten_cnf(lits, offsets) -> Vector{Vector{Int32}}

Inverse of `flatten_cnf`.
"""
function unflatten_cnf(lits::Vector{Int32}, offsets::Vector{Int32})
    nclauses = length(offsets) - 1
    out = Vector{Vector{Int32}}(undef, nclauses)
    @inbounds for i in 1:nclauses
        a0 = offsets[i]
        b0 = offsets[i+1]
        if b0 <= a0
            out[i] = Int32[]
        else
            # offsets are 0-based; Julia arrays are 1-based
            a = Int(a0) + 1
            b = Int(b0)
            out[i] = lits[a:b]
        end
    end
    return out
end

"""
    infer_nvars(cnf) -> Int

Infer number of variables as maximum absolute literal.
"""
function infer_nvars(cnf::Vector{<:AbstractVector{<:Integer}})
    m = 0
    @inbounds for c in cnf
        for lit in c
            a = abs(Int(lit))
            if a > m
                m = a
            end
        end
    end
    return m
end

# -----------------------------
# Low-level C calls
# -----------------------------

# int cadical_mine_learned_cnf(...);
function _ccall_mine_learned(in_lits::Vector{Int32}, in_offsets::Vector{Int32},
    nclauses::Int32, nvars::Int32,
    conflict_limit::Int32, max_len::Int32, max_lbd::Int32)
    out_lits_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_offs_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_nclauses = Ref{Int32}(0)
    out_nlits = Ref{Int32}(0)

    ok = ccall((:cadical_mine_learned_cnf, lib), Cint,
        (Ptr{Int32}, Ptr{Int32}, Int32, Int32, Int32, Int32, Int32,
            Ref{Ptr{Int32}}, Ref{Ptr{Int32}}, Ref{Int32}, Ref{Int32}),
        pointer(in_lits), pointer(in_offsets), nclauses, nvars,
        conflict_limit, max_len, max_lbd,
        out_lits_ptr, out_offs_ptr, out_nclauses, out_nlits)

    return ok, out_lits_ptr, out_offs_ptr, out_nclauses, out_nlits
end

# int cadical_solve_and_mine(...);
function _ccall_solve_and_mine(in_lits::Vector{Int32}, in_offsets::Vector{Int32},
    nclauses::Int32, nvars::Int32,
    conflict_limit::Int32, max_len::Int32, max_lbd::Int32)
    out_lits_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_offs_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_nclauses = Ref{Int32}(0)
    out_nlits = Ref{Int32}(0)
    out_model_ptr = Ref{Ptr{Int32}}(C_NULL)

    res = ccall((:cadical_solve_and_mine, lib), Cint,
        (Ptr{Int32}, Ptr{Int32}, Int32, Int32, Int32, Int32, Int32,
            Ref{Ptr{Int32}}, Ref{Ptr{Int32}}, Ref{Int32}, Ref{Int32},
            Ref{Ptr{Int32}}),
        pointer(in_lits), pointer(in_offsets), nclauses, nvars,
        conflict_limit, max_len, max_lbd,
        out_lits_ptr, out_offs_ptr, out_nclauses, out_nlits,
        out_model_ptr)

    return res, out_lits_ptr, out_offs_ptr, out_nclauses, out_nlits, out_model_ptr
end

# -----------------------------
# Public API
# -----------------------------

"""
    mine_learned(cnf; nvars=infer_nvars(cnf), conflict_limit=20_000, max_len=3, max_lbd=0)
        -> learned::Vector{Vector{Int32}}

Run CaDiCaL for a limited number of conflicts and return learned clauses.
- `max_lbd` is accepted for API compatibility but currently ignored (C++ side does not expose LBD via Learner).
"""
function mine_learned(cnf::Vector{<:AbstractVector{<:Integer}};
    nvars::Integer=infer_nvars(cnf),
    conflict_limit::Integer=20_000,
    max_len::Integer=3,
    max_lbd::Integer=0)

    in_lits, in_offsets = flatten_cnf(cnf)
    nclauses = Int32(length(cnf))

    ok, out_lits_ptr, out_offs_ptr, out_nclauses, out_nlits =
        _ccall_mine_learned(in_lits, in_offsets,
            nclauses, Int32(nvars),
            Int32(conflict_limit), Int32(max_len), Int32(max_lbd))

    ok == 0 && error("cadical_mine_learned_cnf failed (ok=0). Check `lib` path: $lib")

    m = Int(out_nclauses[])
    nl = Int(out_nlits[])

    offs_view = unsafe_wrap(Vector{Int32}, out_offs_ptr[], m + 1; own=false)
    lits_view = unsafe_wrap(Vector{Int32}, out_lits_ptr[], nl; own=false)

    learned = unflatten_cnf(copy(lits_view), copy(offs_view))

    Libc.free(out_lits_ptr[])
    Libc.free(out_offs_ptr[])

    return learned
end

"""
    cadical_solve_and_mine(cnf; nvars=infer_nvars(cnf), conflict_limit=0, max_len=3, max_lbd=0)
        -> (status::Symbol, model::Vector{Int32}, learned::Vector{Vector{Int32}}, stats::CDCLStats)

Solve CNF using CaDiCaL (or stop early if `conflict_limit > 0`) and return:
- `status`: `:sat`, `:unsat`, or `:unknown`
- `model`: length `nvars`, encoding assignment as ±var_id, or 0 if unknown
- `learned`: learned clauses collected during the run
- `stats`: CDCLStats with decisions, conflicts, propagations

Notes:
- If `conflict_limit <= 0`, CaDiCaL may solve to completion.
- If status is `:unknown`, `model` may be all zeros (by current C++ implementation).
- `max_lbd` is accepted for API compatibility but currently ignored.
- This is an alias that uses CaDiCaL backend (not Kissat)
"""
function cadical_solve_and_mine(cnf::Vector{<:AbstractVector{<:Integer}};
    nvars::Integer=infer_nvars(cnf),
    conflict_limit::Integer=0,
    max_len::Integer=3,
    max_lbd::Integer=0)

    in_lits, in_offsets = flatten_cnf(cnf)
    nclauses = Int32(length(cnf))

    res, out_lits_ptr, out_offs_ptr, out_nclauses, out_nlits, out_model_ptr =
        _ccall_solve_and_mine(in_lits, in_offsets,
            nclauses, Int32(nvars),
            Int32(conflict_limit), Int32(max_len), Int32(max_lbd))

    status = res == 10 ? :sat : res == 20 ? :unsat : :unknown

    # Copy model
    model_view = unsafe_wrap(Vector{Int32}, out_model_ptr[], Int(nvars); own=false)
    model = copy(model_view)

    # Copy learned clauses
    m = Int(out_nclauses[])
    nl = Int(out_nlits[])

    offs_view = unsafe_wrap(Vector{Int32}, out_offs_ptr[], m + 1; own=false)
    lits_view = unsafe_wrap(Vector{Int32}, out_lits_ptr[], nl; own=false)
    learned = unflatten_cnf(copy(lits_view), copy(offs_view))

    # Free C buffers
    Libc.free(out_model_ptr[])
    Libc.free(out_lits_ptr[])
    Libc.free(out_offs_ptr[])

    return status, model, learned
end

"""
    parse_cnf_file(path::String) -> (cnf::Vector{Vector{Int}}, nvars::Int)

Parse a DIMACS CNF file from `path`. Returns list of clauses and the number of variables.
"""
function parse_cnf_file(path::String)
    cnf = Vector{Vector{Int}}()
    nvars = 0
    current_clause = Int[]

    for line in eachline(path)
        sline = strip(line)
        isempty(sline) && continue
        startswith(sline, "c") && continue
        startswith(sline, "%") && continue

        if startswith(sline, "p")
            parts = split(sline)
            if length(parts) >= 3
                nvars = parse(Int, parts[3])
            end
            continue
        end

        for token in split(sline)
            val = tryparse(Int, token)
            val === nothing && continue

            if val == 0
                !isempty(current_clause) && push!(cnf, copy(current_clause))
                empty!(current_clause)
            else
                push!(current_clause, val)
                nvars = max(nvars, abs(val))
            end
        end
    end

    !isempty(current_clause) && push!(cnf, current_clause)

    return cnf, nvars
end

# -----------------------------
# CDCL Statistics API
# -----------------------------

# int cadical_solve_with_stats(...)
function _ccall_solve_with_stats(in_lits::Vector{Int32}, in_offsets::Vector{Int32},
    nclauses::Int32, nvars::Int32)
    out_decisions = Ref{Int64}(0)
    out_conflicts = Ref{Int64}(0)
    out_propagations = Ref{Int64}(0)
    out_restarts = Ref{Int64}(0)
    out_model_ptr = Ref{Ptr{Int32}}(C_NULL)

    res = ccall((:cadical_solve_with_stats, lib), Cint,
        (Ptr{Int32}, Ptr{Int32}, Int32, Int32,
            Ref{Int64}, Ref{Int64}, Ref{Int64}, Ref{Int64},
            Ref{Ptr{Int32}}),
        pointer(in_lits), pointer(in_offsets), nclauses, nvars,
        out_decisions, out_conflicts, out_propagations, out_restarts,
        out_model_ptr)

    return res, out_decisions, out_conflicts, out_propagations, out_restarts, out_model_ptr
end

"""
    solve_with_stats(cnf; nvars=infer_nvars(cnf))
        -> (status::Symbol, stats::NamedTuple, model::Vector{Int32})

Solve CNF and return CDCL solving statistics for comparison with tensor network approaches.

Returns:
- `status`: `:sat`, `:unsat`, or `:unknown`
- `stats`: NamedTuple containing:
  - `decisions`: number of decision made during solving
  - `conflicts`: number of conflicts encountered
  - `propagations`: number of unit propagations
  - `restarts`: number of restarts
- `model`: length `nvars`, encoding assignment as ±var_id, or 0 if unknown

This is useful for comparing CDCL solving behavior with tensor network-based approaches.
"""
function solve_with_stats(cnf::Vector{<:AbstractVector{<:Integer}};
    nvars::Integer=infer_nvars(cnf))

    in_lits, in_offsets = flatten_cnf(cnf)
    nclauses = Int32(length(cnf))

    res, out_decisions, out_conflicts, out_propagations, out_restarts, out_model_ptr =
        _ccall_solve_with_stats(in_lits, in_offsets, nclauses, Int32(nvars))

    status = res == 10 ? :sat : res == 20 ? :unsat : :unknown

    stats = (
        decisions=out_decisions[],
        conflicts=out_conflicts[],
        propagations=out_propagations[],
        restarts=out_restarts[]
    )

    # Copy model
    model_view = unsafe_wrap(Vector{Int32}, out_model_ptr[], Int(nvars); own=false)
    model = copy(model_view)

    # Free C buffers
    Libc.free(out_model_ptr[])

    return status, stats, model
end

# -----------------------------
# CDCL Decision Sequence API
# -----------------------------

# int cadical_solve_with_decisions(...)
function _ccall_solve_with_decisions(in_lits::Vector{Int32}, in_offsets::Vector{Int32},
    nclauses::Int32, nvars::Int32)
    out_decision_vars_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_n_decisions = Ref{Int32}(0)
    out_conflicts = Ref{Int64}(0)
    out_model_ptr = Ref{Ptr{Int32}}(C_NULL)

    res = ccall((:cadical_solve_with_decisions, lib), Cint,
        (Ptr{Int32}, Ptr{Int32}, Int32, Int32,
            Ref{Ptr{Int32}}, Ref{Int32}, Ref{Int64},
            Ref{Ptr{Int32}}),
        pointer(in_lits), pointer(in_offsets), nclauses, nvars,
        out_decision_vars_ptr, out_n_decisions, out_conflicts,
        out_model_ptr)

    return res, out_decision_vars_ptr, out_n_decisions, out_conflicts, out_model_ptr
end

"""
    solve_with_decisions(cnf; nvars=infer_nvars(cnf))
        -> (status::Symbol, decision_vars::Vector{Int32}, n_conflicts::Int, model::Vector{Int32})

Solve CNF and return the VSIDS decision variable sequence.

Returns:
- `status`: `:sat`, `:unsat`, or `:unknown`
- `decision_vars`: array of decision variable IDs (in order of selection by VSIDS)
- `n_conflicts`: number of conflicts encountered
- `model`: length `nvars`, encoding assignment as ±var_id, or 0 if unknown

This is useful for comparing CDCL/VSIDS variable selection with MinGamma.
"""
function solve_with_decisions(cnf::Vector{<:AbstractVector{<:Integer}};
    nvars::Integer=infer_nvars(cnf))

    in_lits, in_offsets = flatten_cnf(cnf)
    nclauses = Int32(length(cnf))

    res, out_decision_vars_ptr, out_n_decisions, out_conflicts, out_model_ptr =
        _ccall_solve_with_decisions(in_lits, in_offsets, nclauses, Int32(nvars))

    status = res == 10 ? :sat : res == 20 ? :unsat : :unknown

    # Copy decision variables
    nd = Int(out_n_decisions[])
    if nd > 0
        decisions_view = unsafe_wrap(Vector{Int32}, out_decision_vars_ptr[], nd; own=false)
        decision_vars = copy(decisions_view)
    else
        decision_vars = Int32[]
    end

    # Copy model
    model_view = unsafe_wrap(Vector{Int32}, out_model_ptr[], Int(nvars); own=false)
    model = copy(model_view)

    # Free C buffers
    if nd > 0
        Libc.free(out_decision_vars_ptr[])
    end
    Libc.free(out_model_ptr[])

    return status, decision_vars, Int(out_conflicts[]), model
end

# -----------------------------
# Rich Feedback for Dual-Process SAT (Phase 1 Implementation)
# -----------------------------

"""
    CDCLFeedback

Rich feedback from CDCL solver to guide System 2.

This struct contains all information needed for S1 → S2 learning:
- UNSAT core: which assumptions caused conflict
- Learned clauses: high-quality clauses discovered
- Metrics: conflicts, propagations, average LBD, etc.
"""
struct CDCLFeedback
    status::Symbol                          # :sat, :unsat, :unknown
    model::Vector{Int32}                    # If SAT (±var encoding)

    # UNSAT core (which assumptions caused conflict)
    unsat_core::Vector{Int}                 # Subset of assumptions

    # High-quality learned clauses
    learned_clauses::Vector{Vector{Int}}    # Short, low-LBD clauses
    learned_lbds::Vector{Int}              # LBD for each learned clause

    # CDCL solving metrics
    decisions::Int
    conflicts::Int
    propagations::Int
    restarts::Int
    avg_lbd::Float64                        # Average LBD during solving
    max_decision_level::Int                 # Deepest backjump
end

function Base.show(io::IO, fb::CDCLFeedback)
    print(io, "CDCLFeedback(:$(fb.status), conflicts=$(fb.conflicts), avg_lbd=$(round(fb.avg_lbd, digits=2)))")
end

# C API wrapper
function _ccall_solve_with_assumptions(
    in_lits::Vector{Int32}, in_offsets::Vector{Int32},
    nclauses::Int32, nvars::Int32,
    assumptions::Vector{Int32},
    conflict_limit::Int32,
    max_learned_len::Int32, max_learned_lbd::Int32
)
    # Output references
    out_model_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_failed_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_n_failed = Ref{Int32}(0)

    out_learned_lits_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_learned_offs_ptr = Ref{Ptr{Int32}}(C_NULL)
    out_n_learned = Ref{Int32}(0)
    out_n_learned_lits = Ref{Int32}(0)
    out_learned_lbds_ptr = Ref{Ptr{Int32}}(C_NULL)

    out_decisions = Ref{Int64}(0)
    out_conflicts = Ref{Int64}(0)
    out_propagations = Ref{Int64}(0)
    out_restarts = Ref{Int64}(0)
    out_avg_lbd = Ref{Float64}(0.0)
    out_max_level = Ref{Int32}(0)

    res = ccall((:cadical_solve_with_assumptions, lib), Cint,
        (Ptr{Int32}, Ptr{Int32}, Int32, Int32,
         Ptr{Int32}, Int32, Int32, Int32, Int32,
         Ref{Ptr{Int32}},
         Ref{Ptr{Int32}}, Ref{Int32},
         Ref{Ptr{Int32}}, Ref{Ptr{Int32}}, Ref{Int32}, Ref{Int32},
         Ref{Ptr{Int32}},
         Ref{Int64}, Ref{Int64}, Ref{Int64}, Ref{Int64},
         Ref{Float64}, Ref{Int32}),
        pointer(in_lits), pointer(in_offsets), nclauses, nvars,
        pointer(assumptions), Int32(length(assumptions)), conflict_limit, max_learned_len, max_learned_lbd,
        out_model_ptr,
        out_failed_ptr, out_n_failed,
        out_learned_lits_ptr, out_learned_offs_ptr, out_n_learned, out_n_learned_lits,
        out_learned_lbds_ptr,
        out_decisions, out_conflicts, out_propagations, out_restarts,
        out_avg_lbd, out_max_level
    )

    return (res, out_model_ptr, out_failed_ptr, out_n_failed,
            out_learned_lits_ptr, out_learned_offs_ptr, out_n_learned, out_n_learned_lits,
            out_learned_lbds_ptr,
            out_decisions, out_conflicts, out_propagations, out_restarts,
            out_avg_lbd, out_max_level)
end

"""
    solve_with_assumptions(cnf, assumptions; nvars, conflict_limit=0, max_learned_len=10, max_learned_lbd=10)
        -> CDCLFeedback

Solve CNF under assumptions and return rich feedback for System 2 learning.

This is the core S1 → S2 communication interface. System 2 proposes a cube (assumptions),
and System 1 (CDCL) returns detailed feedback about why it succeeded or failed.

# Arguments
- `cnf`: Vector of clauses
- `assumptions`: Vector of literals to assume (e.g., cube from S2)
- `nvars`: Number of variables (inferred if not provided)
- `conflict_limit`: Conflict limit for probing (0 = unlimited, solve to completion)
- `max_learned_len`: Maximum length of learned clauses to return
- `max_learned_lbd`: Maximum LBD of learned clauses to return

# Returns
- `CDCLFeedback` with status, model, UNSAT core, learned clauses, and metrics
- Status can be `:sat`, `:unsat`, or `:unknown` (reached conflict limit)

# Example
```julia
# S2 proposes cube
cube = [1, -5, 7]

# Probing with conflict limit
feedback = solve_with_assumptions(cnf, cube; conflict_limit=5000, max_learned_lbd=5)

if feedback.status == :unsat
    # S2 learns from failure
    println("UNSAT core: ", feedback.unsat_core)  # e.g., [1, 7]
    println("Avg LBD: ", feedback.avg_lbd)        # e.g., 8.3 (hard region)
elseif feedback.status == :unknown
    # Reached conflict limit, learned clauses still useful
    println("Probing stopped at", feedback.conflicts, " conflicts")
    println("Learned", length(feedback.learned_clauses), " clauses")
end
```
"""
function solve_with_assumptions(
    cnf::Vector{<:AbstractVector{<:Integer}},
    assumptions::Vector{<:Integer};
    nvars::Integer=infer_nvars(cnf),
    conflict_limit::Integer=0,
    max_learned_len::Integer=10,
    max_learned_lbd::Integer=10
)
    in_lits, in_offsets = flatten_cnf(cnf)
    nclauses = Int32(length(cnf))
    assumptions_i32 = Int32.(assumptions)

    (res, out_model_ptr, out_failed_ptr, out_n_failed,
     out_learned_lits_ptr, out_learned_offs_ptr, out_n_learned, out_n_learned_lits,
     out_learned_lbds_ptr,
     out_decisions, out_conflicts, out_propagations, out_restarts,
     out_avg_lbd, out_max_level) = _ccall_solve_with_assumptions(
        in_lits, in_offsets, nclauses, Int32(nvars),
        assumptions_i32, Int32(conflict_limit),
        Int32(max_learned_len), Int32(max_learned_lbd)
    )

    status = res == 10 ? :sat : res == 20 ? :unsat : :unknown

    # Extract model
    model_view = unsafe_wrap(Vector{Int32}, out_model_ptr[], Int(nvars); own=false)
    model = copy(model_view)

    # Extract UNSAT core (failed assumptions)
    n_failed = Int(out_n_failed[])
    if n_failed > 0
        failed_view = unsafe_wrap(Vector{Int32}, out_failed_ptr[], n_failed; own=false)
        unsat_core = Int.(copy(failed_view))
    else
        unsat_core = Int[]
    end

    # Extract learned clauses
    n_learned = Int(out_n_learned[])
    n_learned_lits = Int(out_n_learned_lits[])
    if n_learned > 0
        offs_view = unsafe_wrap(Vector{Int32}, out_learned_offs_ptr[], n_learned + 1; own=false)
        lits_view = unsafe_wrap(Vector{Int32}, out_learned_lits_ptr[], n_learned_lits; own=false)
        lbds_view = unsafe_wrap(Vector{Int32}, out_learned_lbds_ptr[], n_learned; own=false)

        learned_clauses = unflatten_cnf(copy(lits_view), copy(offs_view))
        learned_lbds = Int.(copy(lbds_view))
    else
        learned_clauses = Vector{Vector{Int}}()
        learned_lbds = Int[]
    end

    feedback = CDCLFeedback(
        status, model,
        unsat_core,
        learned_clauses, learned_lbds,
        Int(out_decisions[]), Int(out_conflicts[]),
        Int(out_propagations[]), Int(out_restarts[]),
        Float64(out_avg_lbd[]), Int(out_max_level[])
    )

    # Free C buffers
    Libc.free(out_model_ptr[])
    n_failed > 0 && Libc.free(out_failed_ptr[])
    if n_learned > 0
        Libc.free(out_learned_lits_ptr[])
        Libc.free(out_learned_offs_ptr[])
        Libc.free(out_learned_lbds_ptr[])
    end

    return feedback
end