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
    out_nlits    = Ref{Int32}(0)

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
    out_nlits    = Ref{Int32}(0)
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

    m  = Int(out_nclauses[])
    nl = Int(out_nlits[])

    offs_view = unsafe_wrap(Vector{Int32}, out_offs_ptr[], m + 1; own=false)
    lits_view = unsafe_wrap(Vector{Int32}, out_lits_ptr[], nl; own=false)

    learned = unflatten_cnf(copy(lits_view), copy(offs_view))

    Libc.free(out_lits_ptr[])
    Libc.free(out_offs_ptr[])

    return learned
end

"""
    solve_and_mine(cnf; nvars=infer_nvars(cnf), conflict_limit=0, max_len=3, max_lbd=0)
        -> (status::Symbol, model::Vector{Int32}, learned::Vector{Vector{Int32}})

Solve CNF (or stop early if `conflict_limit > 0`) and return:
- `status`: `:sat`, `:unsat`, or `:unknown`
- `model`: length `nvars`, encoding assignment as ±var_id, or 0 if unknown
- `learned`: learned clauses collected during the run

Notes:
- If `conflict_limit <= 0`, CaDiCaL may solve to completion.
- If status is `:unknown`, `model` may be all zeros (by current C++ implementation).
- `max_lbd` is accepted for API compatibility but currently ignored.
"""
function solve_and_mine(cnf::Vector{<:AbstractVector{<:Integer}};
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
    m  = Int(out_nclauses[])
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