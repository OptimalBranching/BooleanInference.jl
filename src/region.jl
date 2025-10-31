struct RegionCacheEntry
    region::Region
    table::BranchingTable
end

mutable struct RegionCacheState  # a collection of region entries
    entries::Dict{Int, RegionCacheEntry}  # region id -> region entry
end
RegionCacheState() = RegionCacheState(Dict{Int, RegionCacheEntry}())

# Global cache shared across all problems during solving
const REGION_CACHE = RegionCacheState()

# Cache region and table together (creates or updates entry)
function cache_region_table!(region::Region, table::BranchingTable)
    REGION_CACHE.entries[region.id] = RegionCacheEntry(region, table)
    return nothing
end

# Get cached region and table by region_id
function get_cached_region(region_id::Int)
    entry = get(REGION_CACHE.entries, region_id, nothing)
    (isnothing(entry) || isnothing(entry.table)) && return nothing, nothing
    return entry.region, entry.table
end

function clear_all_region_caches!()
    empty!(REGION_CACHE.entries)
    return nothing
end

