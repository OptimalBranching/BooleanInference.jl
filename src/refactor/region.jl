struct RegionContraction  # tensor and vars that are contracted to form the region
    tensor::AbstractArray{Tropical{Float64}}
    vars::Vector{Int}
end

mutable struct RegionCacheEntry  # one single region and its contraction
    region::Region
    contraction::Union{Nothing, RegionContraction}
end
RegionCacheEntry(region::Region) = RegionCacheEntry(region, nothing)

mutable struct RegionCacheState  # a collection of region entries
    entries::Dict{Int, RegionCacheEntry}  # region id -> region entry
    last_region_id::Union{Nothing, Int}
end
RegionCacheState() = RegionCacheState(Dict{Int, RegionCacheEntry}(), nothing)

struct RegionCache  # a collection of region cache states
    data::IdDict{UInt, RegionCacheState}
end

const REGION_CACHE = RegionCache(IdDict{UInt, RegionCacheState}())

function cache_region!(problem::TNProblem, region::Region)
    # get or create the region cache state for the problem
    state = get!(REGION_CACHE.data, objectid(problem)) do
        RegionCacheState()
    end
    state.entries[region.id] = RegionCacheEntry(region)
    state.last_region_id = region.id
    return nothing
end

function get_cached_region_entry(problem::TNProblem, region_id::Int)
    state = get(REGION_CACHE.data, objectid(problem), nothing)
    isnothing(state) && return nothing
    get(state.entries, region_id, nothing)
end
function get_cached_region_entry(problem::TNProblem)
    # get the last region id from the state
    state = get(REGION_CACHE.data, objectid(problem), nothing)
    (isnothing(state) || isnothing(state.last_region_id)) && return nothing
    get(state.entries, state.last_region_id, nothing)
end

function get_cached_region(problem::TNProblem)
    entry = get_cached_region_entry(problem)
    isnothing(entry) && return nothing
    entry.region
end

function cache_region_contraction!(problem::TNProblem, tensor::AbstractArray{Tropical{Float64}}, vars::Vector{Int}; region_id::Union{Nothing, Int}=nothing)
    entry = isnothing(region_id) ? get_cached_region_entry(problem) : get_cached_region_entry(problem, region_id)
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

function clear_region_cache!(problem::TNProblem)
    delete!(REGION_CACHE.data, objectid(problem))
    return nothing
end

function clear_all_region_caches!()
    empty!(REGION_CACHE.data)
    return nothing
end

