struct Region
    id::Int
    tensors::Vector{Int}
    inner_vars::Vector{Int}
    boundary_vars::Vector{Int}
end

function Base.show(io::IO, region::Region)
    print(io, "Region(focus=$(region.id), tensors=$(length(region.tensors)), inner_vars=$(region.inner_vars), boundary_vars=$(region.boundary_vars))")
end

function get_region_tensor_type(problem::TNProblem, region::Region)
    symbols = Symbol[]
    fanin = Vector{Int}[]
    fanout = Vector{Int}[]
    active_vars = get_unfixed_vars(problem, region.tensors)
    for tensor_id in region.tensors
        push!(symbols, problem.static.tensor_symbols[tensor_id])
        push!(fanin, problem.static.tensor_fanin[tensor_id])
        push!(fanout, problem.static.tensor_fanout[tensor_id])
    end
    return symbols, fanin, fanout, active_vars
end

struct RegionCacheEntry
    region::Region
    table::BranchingTable
end

mutable struct RegionCacheState
    entries::Dict{Int, RegionCacheEntry}
end

RegionCacheState() = RegionCacheState(Dict{Int, RegionCacheEntry}())

# global region cache
const REGION_CACHE = RegionCacheState()

function cache_region!(region::Region, table::BranchingTable)
    REGION_CACHE.entries[region.id] = RegionCacheEntry(region, table)
    return nothing
end

function get_cached_region(region_id::Int)
    entry = get(REGION_CACHE.entries, region_id, nothing)
    (isnothing(entry) || isnothing(entry.table)) && return nothing, nothing
    return entry.region, entry.table
end

function clear_all_region_caches!()
    empty!(REGION_CACHE.entries)
    return nothing
end

