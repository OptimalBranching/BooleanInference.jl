struct RegionContraction
    tensor::AbstractArray{Tropical{Float64}}
    vars::Vector{Int}
end

mutable struct RegionCacheEntry
    region::Region
    contraction::Union{Nothing,RegionContraction}
end
RegionCacheEntry(region::Region) = RegionCacheEntry(region, nothing)

mutable struct RegionCacheState
    entries::Dict{Int,RegionCacheEntry}
    last_region_id::Union{Nothing,Int}
end
RegionCacheState() = RegionCacheState(Dict{Int,RegionCacheEntry}(), nothing)

struct RegionCache
    data::IdDict{UInt,RegionCacheState}
end

const REGION_CACHE = RegionCache(IdDict{UInt,RegionCacheState}())

function cache_region!(problem::TNProblem, region::Region)
    state = get!(REGION_CACHE.data, objectid(problem)) do
        RegionCacheState()
    end
    state.entries[region.id] = RegionCacheEntry(region)
    state.last_region_id = region.id
    return nothing
end

function get_cached_region_entry(problem::TNProblem)
    state = get(REGION_CACHE.data, objectid(problem), nothing)
    state === nothing && return nothing
    region_id = state.last_region_id
    region_id === nothing && return nothing
    return get(state.entries, region_id, nothing)
end

function get_cached_region_entry(problem::TNProblem, region_id::Int)
    state = get(REGION_CACHE.data, objectid(problem), nothing)
    state === nothing && return nothing
    return get(state.entries, region_id, nothing)
end

function get_cached_region(problem::TNProblem)
    entry = get_cached_region_entry(problem)
    isnothing(entry) && return nothing
    return entry.region
end

function cache_region_contraction!(
    problem::TNProblem,
    tensor::AbstractArray{Tropical{Float64}},
    vars::Vector{Int};
    region_id::Union{Nothing,Int}=nothing,
)
    entry = isnothing(region_id) ? get_cached_region_entry(problem) :
            get_cached_region_entry(problem, region_id)
    isnothing(entry) && error("No cached region entry available for contraction caching.")
    entry.contraction = RegionContraction(tensor, vars)
    return entry.contraction
end

function get_cached_region_contraction(
    problem::TNProblem;
    region_id::Union{Nothing,Int}=nothing,
)
    entry = isnothing(region_id) ? get_cached_region_entry(problem) :
            get_cached_region_entry(problem, region_id)
    isnothing(entry) && return nothing
    isnothing(entry.contraction) && return nothing
    contraction = entry.contraction
    return contraction.tensor, contraction.vars
end

function set_last_region!(problem::TNProblem, region_id::Int)
    state = get(REGION_CACHE.data, objectid(problem), nothing)
    state === nothing && return nothing
    haskey(state.entries, region_id) || return nothing
    state.last_region_id = region_id
    return nothing
end

function clear_region_cache!(problem::TNProblem)
    delete!(REGION_CACHE.data, objectid(problem))
    return nothing
end

function clear_all_region_caches!()
    empty!(REGION_CACHE.data)
    return nothing
end
