struct RegionCache
    data::IdDict{UInt, Region}
end

const REGION_CACHE = RegionCache(IdDict{UInt, Region}())

function cache_region!(problem::TNProblem, region::Region)
    REGION_CACHE.data[objectid(problem)] = region
    return nothing
end

function get_cached_region(problem::TNProblem)
    return get(REGION_CACHE.data, objectid(problem), nothing)
end

function clear_region_cache!(problem::TNProblem)
    delete!(REGION_CACHE.data, objectid(problem))
    return nothing
end

function clear_all_region_caches!()
    empty!(REGION_CACHE.data)
    return nothing
end

