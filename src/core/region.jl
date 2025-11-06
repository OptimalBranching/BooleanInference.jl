struct Region
    id::Int
    tensors::Vector{Int}
    inner_vars::Vector{Int}
    boundary_vars::Vector{Int}
end

function Base.show(io::IO, region::Region)
    print(io, "Region(focus=$(region.id), tensors=$(length(region.tensors)), inner_vars=$(region.inner_vars), boundary_vars=$(region.boundary_vars))")
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

