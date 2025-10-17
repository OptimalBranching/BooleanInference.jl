# Region cache management
# 
# This module provides explicit caching of Region objects computed during select_variables.
# Using an explicit cache manager makes the side effects visible and keeps TNProblem immutable.

"""
    RegionCache

Global cache for Region objects, keyed by problem instance (using objectid).
"""
struct RegionCache
    data::IdDict{UInt, Region}
end

"""
    REGION_CACHE

Global singleton RegionCache instance.
"""
const REGION_CACHE = RegionCache(IdDict{UInt, Region}())

"""
    cache_region!(problem::TNProblem, region::Region)

Store a Region in the global cache, associated with the given problem instance.
This is called by `select_variables` to pass Region information to `branching_table`.

# Example
```julia
region = k_neighboring(...)
cache_region!(problem, region)
```
"""
function cache_region!(problem::TNProblem, region::Region)
    REGION_CACHE.data[objectid(problem)] = region
    return nothing
end

"""
    get_cached_region(problem::TNProblem)

Retrieve the cached Region for the given problem instance, or `nothing` if not found.

# Example
```julia
region = get_cached_region(problem)
if region === nothing
    error("No cached region found")
end
```
"""
function get_cached_region(problem::TNProblem)
    return get(REGION_CACHE.data, objectid(problem), nothing)
end

"""
    clear_region_cache!(problem::TNProblem)

Remove the cached Region for the given problem instance.
Useful for cleanup, though not strictly necessary (old problems will be GC'd).
"""
function clear_region_cache!(problem::TNProblem)
    delete!(REGION_CACHE.data, objectid(problem))
    return nothing
end

"""
    clear_all_region_caches!()

Clear all cached Regions. Useful for testing or manual cleanup.
"""
function clear_all_region_caches!()
    empty!(REGION_CACHE.data)
    return nothing
end

