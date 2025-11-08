function resolve_data_dir(parts::AbstractString...)
    base = normpath(joinpath(@__DIR__, ".."))
    dir = joinpath(base, "data", parts...)
    isdir(dir) || mkpath(dir)
    return dir
end

# Helper function for finding executables in PATH
function find_executable_in_path(cmd::String, name::String)
    try
        return strip(read(`which $cmd`, String))
    catch
        error("$name not found in PATH. Please provide explicit path or install it.")
    end
end

# Helper function for validating executable path
function validate_executable_path(path::Union{String, Nothing}, name::String)
    if isnothing(path)
        return nothing
    elseif !isfile(path)
        error("File $path for $name does not exist")
    else
        return path
    end
end