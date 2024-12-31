struct SubBIP{N}
    vs::Vector{Int}
    edges::Vector{Int}
    outside_vs_ind::Vector{Int}
    sub_tensors::Array{Tropical{Float64},N}
end

struct KNeighborSelector <: AbstractSelector
    k::Int
    initial_vertex_strategy::Int # 1: maximum, 2: minimum,3: minimum weight
end

struct Smallest2NeighborSelector <: AbstractSelector end

function OptimalBranchingCore.select_variables(p::BooleanInferenceProblem,bs::AbstractBranchingStatus,m::M, selector::KNeighborSelector) where{M<:AbstractMeasure}
    he2v,edge_list,decided_v = subhg(p, bs)
    undecided_literals = setdiff(1:p.literal_num,decided_v)

    v2he = [count(x -> i ∈ x, he2v) for i in undecided_literals]
    index = argmin(x-> iszero(v2he[x]) ? Inf : v2he[x],1:length(v2he))
    initial_v = undecided_literals[index]
    # initial_v = selector.initial_vertex_strategy == 1 ? maximum(undecided_literals) : minimum(undecided_literals)
    
    vs, edges,outside_vs_ind  = k_neighboring(he2v,initial_v, selector.k)

    return SubBIP{length(vs)}(vs, edge_list[edges], outside_vs_ind, gen_sub_tensor(p, bs, vs, edges,he2v,edge_list))
end

function OptimalBranchingCore.select_variables(p::BooleanInferenceProblem,bs::AbstractBranchingStatus,m::M, selector::Smallest2NeighborSelector) where{M<:AbstractMeasure}
    he2v,edge_list,decided_v = subhg(p, bs)
    undecided_literals = setdiff(1:p.literal_num,decided_v)

    minval = -Inf
    local min_vs, min_edges, min_outside_vs_ind
    for v in undecided_literals
        vs, edges,outside_vs_ind = k_neighboring(he2v,v, 2)
        if length(outside_vs_ind)/length(vs) > minval
            minval = length(outside_vs_ind)/length(vs)
            min_vs = vs
            min_edges = edges
            min_outside_vs_ind = outside_vs_ind
        end
    end
    
    return SubBIP{length(min_vs)}(min_vs, edge_list[min_edges], min_outside_vs_ind, gen_sub_tensor(p, bs, min_vs, min_edges,he2v,edge_list))
end


function k_neighboring(he2v::Vector{Vector{Int}}, vs, k::Int)
    for _ in 1:k-1
        vs = first(_neighboring(he2v, vs))
    end
    vs, edges = _neighboring(he2v, vs)
   
    outside_vs_ind = [ind for ind in 1:length(vs) if any([vs[ind] ∈ v for v in he2v[setdiff(1:length(he2v),edges)]])]
    return vs, edges,outside_vs_ind
end
_neighboring(he2v::Vector{Vector{Int}}, vs::Int) = _neighboring(he2v, [vs])
function _neighboring(he2v::Vector{Vector{Int}}, vs::Vector{Int})
    edges = sort([i for i in 1:length(he2v) if !isempty(he2v[i] ∩ vs)])
    vs = sort(reduce(∪, he2v[edges]))
    return vs, edges
end

function subhg(bip::BooleanInferenceProblem, bs::AbstractBranchingStatus)
    decided_v = [ i for i in 1:bip.literal_num if readbit(bs.decided_mask, i) == 1]
    return [setdiff(bip.he2v[e], decided_v) for e in 1: length(bip.he2v) if bs.undecided_literals[e] > 0],[e for e in 1: length(bip.he2v) if bs.undecided_literals[e] > 0],decided_v
end

function gen_sub_tensor(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, vs::Vector{Int}, edges::Vector{Int}, he2v::Vector{Vector{Int}},edge_list::Vector{Int})
    eincode = EinCode(he2v[edges], vs)
	optcode = optimize_code(eincode, uniformsize(eincode, 2), GreedyMethod())

    sub_tensors = optcode([vec2tensor(slice_tensor(p.tensors[e],bs.decided_mask,bs.config,p.he2v[e])) for e in edge_list[edges]]...)
    return sub_tensors
end