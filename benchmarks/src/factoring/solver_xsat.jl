struct XSatResult
    status::Symbol                 # :sat | :unsat | :unknown
    model::Union{Nothing,Dict{Int,Bool}}  # 变量 -> 取值（仅 SAT 有）
    raw::String                    # 原始控制台输出，便于调试/记录
end

"""
    run_xsat_and_parse(exec::AbstractString, aig_path::AbstractString) -> XSatResult

Run XSAT (e.g., exec="/path/to/xsat") and parse the output of `-i aig_path`.
Parse the `s ...` status line and one or more `v ...` assignment lines (DIMACS style, terminated by 0).
"""
function run_xsat_and_parse(exec::AbstractString, aig_path::AbstractString)::XSatResult
    raw = read(`$exec -i $aig_path`, String)

    status =
        occursin(r"(?m)^s\s+SATISFIABLE\b", raw) ? :sat :
        occursin(r"(?m)^s\s+UNSATISFIABLE\b", raw) ? :unsat : :unknown

    model = nothing
    if status == :sat
        lits = Int[]
        for m in eachmatch(r"(?m)^v\s+([^\n]+)", raw)
            append!(lits, parse.(Int, split(m.captures[1])))
        end
        filter!(!=(0), lits)

        d = Dict{Int,Bool}()
        for lit in lits
            v = abs(lit)
            d[v] = lit > 0
        end
        model = d
    end

    return XSatResult(status, model, raw)
end