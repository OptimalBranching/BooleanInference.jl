function resolve_data_dir(parts::AbstractString...)
    base = normpath(joinpath(@__DIR__, ".."))
    dir = joinpath(base, "data", parts...)
    isdir(dir) || mkpath(dir)
    return dir
end

function write_jsonl(io::IO, obj)
    JSON3.write(io, obj)
    write(io, '\n')
end

function read_jsonl(path::AbstractString)
    objs = Any[]
    open(path, "r") do io
        for line in eachline(io)
            isempty(strip(line)) && continue
            push!(objs, JSON3.read(line))
        end
    end
    return objs
end