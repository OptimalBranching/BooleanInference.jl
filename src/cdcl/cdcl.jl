using Libdl

const SAT_CODE = 10
const UNSAT_CODE = 20

struct EasySATLib
    handle::Ptr{Cvoid}
    new::Ptr{Cvoid}
    free::Ptr{Cvoid}
    add_clause::Ptr{Cvoid}
    solve::Ptr{Cvoid}
    get_model::Ptr{Cvoid}
    get_learnt_count::Ptr{Cvoid}
    get_learnt_size::Ptr{Cvoid}
    get_learnt_clause::Ptr{Cvoid}
end

function libeasysat_path()
    if Sys.isapple()
        return joinpath(@__DIR__, "libeasysat.dylib")
    elseif Sys.iswindows()
        return joinpath(@__DIR__, "libeasysat.dll")
    else
        return joinpath(@__DIR__, "libeasysat.so")
    end
end

function load_easysat(libpath::AbstractString)
    handle = Libdl.dlopen(libpath)
    return EasySATLib(
        handle,
        Libdl.dlsym(handle, :easysat_new),
        Libdl.dlsym(handle, :easysat_free),
        Libdl.dlsym(handle, :easysat_add_clause),
        Libdl.dlsym(handle, :easysat_solve),
        Libdl.dlsym(handle, :easysat_get_model),
        Libdl.dlsym(handle, :easysat_get_learnt_count),
        Libdl.dlsym(handle, :easysat_get_learnt_size),
        Libdl.dlsym(handle, :easysat_get_learnt_clause),
    )
end

function close_easysat(lib::EasySATLib)
    Libdl.dlclose(lib.handle)
    return nothing
end

"""
    parse_cnf_file(path::AbstractString)

Parse a DIMACS .cnf file into `(cnf, nvars)` where `cnf` is
`Vector{Vector{Int}}` and `nvars` is the variable count.
"""
function parse_cnf_file(path::AbstractString)
    cnf = Vector{Vector{Int}}()
    nvars = 0
    clause = Int[]

    open(path, "r") do io
        for line in eachline(io)
            s = strip(line)
            if isempty(s) || startswith(s, 'c')
                continue
            end
            if startswith(s, 'p')
                parts = split(s)
                if length(parts) >= 4 && parts[2] == "cnf"
                    nvars = parse(Int, parts[3])
                end
                continue
            end

            for tok in split(s)
                lit = parse(Int, tok)
                if lit == 0
                    push!(cnf, clause)
                    clause = Int[]
                else
                    push!(clause, lit)
                    v = abs(lit)
                    if v > nvars
                        nvars = v
                    end
                end
            end
        end
    end

    if !isempty(clause)
        push!(cnf, clause)
    end

    return cnf, nvars
end

"""
    solve_cdcl(cnf::Vector{Vector{Int}}; nvars::Int=0, libpath::AbstractString=libeasysat_path())

Solve CNF using EasySAT C++ backend. Returns (sat::Bool, model::Vector{Int}, learnt::Vector{Vector{Int}}).
Model is per-variable assignment in {-1,0,1}. Learned clauses are all clauses learned during solving.
"""
function solve_cdcl(cnf::Vector{Vector{Int}}; nvars::Int=0, libpath::AbstractString=libeasysat_path())
    if nvars <= 0
        maxvar = 0
        for clause in cnf
            for lit in clause
                v = abs(lit)
                if v > maxvar
                    maxvar = v
                end
            end
        end
        nvars = maxvar
    end

    if nvars <= 0
        return (true, Int[], Vector{Vector{Int}}())
    end

    lib = load_easysat(libpath)
    handle = ccall(lib.new, Ptr{Cvoid}, (Cint,), nvars)
    if handle == C_NULL
        close_easysat(lib)
        error("easysat_new failed")
    end

    try
        for clause in cnf
            if isempty(clause)
                ccall(lib.add_clause, Cint,
                      (Ptr{Cvoid}, Ptr{Cint}, Cint),
                      handle, Ptr{Cint}(C_NULL), 0)
                continue
            end
            lits = Vector{Cint}(clause)
            ccall(lib.add_clause, Cint,
                  (Ptr{Cvoid}, Ptr{Cint}, Cint),
                  handle, lits, length(lits))
        end

        res = ccall(lib.solve, Cint, (Ptr{Cvoid},), handle)
        sat = res == SAT_CODE

        model = Int[]
        if sat
            tmp = Vector{Cint}(undef, nvars)
            ccall(lib.get_model, Cint,
                  (Ptr{Cvoid}, Ptr{Cint}, Cint),
                  handle, tmp, nvars)
            model = Int.(tmp)
        end

        learnt = Vector{Vector{Int}}()
        nlearnt = ccall(lib.get_learnt_count, Csize_t, (Ptr{Cvoid},), handle)
        if nlearnt > 0
            for i in 0:(nlearnt - 1)
                sz = ccall(lib.get_learnt_size, Csize_t, (Ptr{Cvoid}, Csize_t), handle, i)
                buf = Vector{Cint}(undef, sz)
                ccall(lib.get_learnt_clause, Cint,
                      (Ptr{Cvoid}, Csize_t, Ptr{Cint}, Cint),
                      handle, i, buf, length(buf))
                push!(learnt, Int.(buf))
            end
        end

        return (sat, model, learnt)
    finally
        ccall(lib.free, Cvoid, (Ptr{Cvoid},), handle)
        close_easysat(lib)
    end
end
