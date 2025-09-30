# The SubBIP struct represents a focused subproblem containing a selected subset of variables along with their associated edges and tensor data.
struct SubBIP{N}
    vs::Vector{Int}
    edges::Vector{Int}
    outside_vs_ind::Vector{Int}
    sub_tensors::Array{Tropical{Float64}, N}
end

function SubBIP(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, vs::Vector{Int})
    he2v, edge_list, decided_v = subhg(p, bs)
    edges = sort([i for i in 1:length(he2v) if (he2v[i] ⊆ vs)])
    outside_vs_ind = [v for v in vs if any(i -> !(i in edges) && (v in he2v[i]), 1:length(he2v))]
    return SubBIP{length(vs)}(vs, edges, outside_vs_ind, gen_sub_tensor(p, bs, vs, edges, he2v, edge_list))
end

struct KNeighborSelector <: AbstractSelector
    k::Int
    initial_vertex_strategy::Int # 1: maximum, 2: minimum,3: minimum weight
end

struct Smallest2NeighborSelector <: AbstractSelector end
struct KaHyParSelector <: AbstractSelector 
    app_domain_size::Int
end

function OptimalBranchingCore.select_variables(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, m::M, selector::KaHyParSelector) where {M <: AbstractMeasure}
    # Extract hyperedges with at least one undecided vertex
    he2v, edge_list, decided_v = subhg(p, bs)
    h = KaHyPar.HyperGraph(hyperedge_to_sparse(he2v))
    imbalance = 1-2*selector.app_domain_size/p.literal_num
    @show imbalance
    parts = KaHyPar.partition(h, 2; configuration=:edge_cut, imbalance)

    zero_num = count(x-> x ≈ 0,parts)
    one_num = length(parts)-zero_num

    part0 = abs(zero_num-selector.app_domain_size) < abs(one_num-selector.app_domain_size) ? findall(iszero,parts) : findall(!iszero,parts)
    return SubBIP(p,bs,part0)
end

function OptimalBranchingCore.select_variables(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, m::M, selector::KNeighborSelector) where {M <: AbstractMeasure}
    # Extract hyperedges with at least one undecided vertex
    he2v, edge_list, decided_v = subhg(p, bs)
    # all undecided variables ordered increasingly
    undecided_variables = setdiff(1:p.literal_num, decided_v)
    
    # he2v[i] represents the undecided literals in the i-th clause.
    v2he = [count(x -> i ∈ x, he2v) for i in undecided_variables]  # i is the index of the undecided literal
    # least frequent occurrence across clauses
    index = argmin(x -> iszero(v2he[x]) ? Inf : v2he[x], 1:length(v2he))
    initial_v = undecided_variables[index]
    # initial_v = selector.initial_vertex_strategy == 1 ? maximum(undecided_literals) : minimum(undecided_literals)

    # start from that variable
    vs, edges, outside_vs_ind = k_neighboring(he2v, initial_v, selector.k)

    return SubBIP{length(vs)}(vs, edge_list[edges], outside_vs_ind, gen_sub_tensor(p, bs, vs, edges, he2v, edge_list))
end

function OptimalBranchingCore.select_variables(p::BooleanInferenceProblem, bs::AbstractBranchingStatus, m::M, selector::Smallest2NeighborSelector) where {M <: AbstractMeasure}
    he2v, edge_list, decided_v = subhg(p, bs)
    undecided_literals = setdiff(1:p.literal_num, decided_v)

    minval = -Inf
    local min_vs, min_edges, min_outside_vs_ind
    for v in undecided_literals
        vs, edges, outside_vs_ind = k_neighboring(he2v, v, 2)
        if length(outside_vs_ind) / length(vs) > minval
            minval = length(outside_vs_ind) / length(vs)
            min_vs = vs
            min_edges = edges
            min_outside_vs_ind = outside_vs_ind
        end
    end

    return SubBIP{length(min_vs)}(min_vs, edge_list[min_edges], min_outside_vs_ind, gen_sub_tensor(p, bs, min_vs, min_edges, he2v, edge_list))
end

function k_neighboring(he2v::Vector{Vector{Int}}, vs, k::Int)
    # Expand k-1 layers (only vertices needed)
    for _ in 1:k-1
        vs = first(_neighboring(he2v, vs))
    end
    # Final expansion: get both vertices and edges
    vs, edges = _neighboring(he2v, vs)

    # Find boundary vertices: vertices in vs that also appear in hyperedges outside the selected edges
    # Optimization: build a set of all vertices in outside hyperedges
    edges_set = Set(edges)
    outside_vertices = Set{Int}()
    for (i, hyperedge) in enumerate(he2v)
        if !(i in edges_set)
            union!(outside_vertices, hyperedge)
        end
    end
    
    # Find indices of vs that are in outside_vertices
    outside_vs_ind = [ind for ind in 1:length(vs) if vs[ind] in outside_vertices]
    
    return vs, edges, outside_vs_ind
end

_neighboring(he2v::Vector{Vector{Int}}, vs::Int) = _neighboring(he2v, [vs])

function _neighboring(he2v::Vector{Vector{Int}}, vs::Vector{Int})
    vs_set = Set(vs)
    edges = [i for i in 1:length(he2v) if !isempty(he2v[i] ∩ vs_set)]
    # Collect all vertices from selected edges
    new_vs = Set{Int}()
    for e in edges
        union!(new_vs, he2v[e])
    end
    vs = sort!(collect(new_vs))
    return vs, edges
end

"""
    subhg(bip::BooleanInferenceProblem, bs::AbstractBranchingStatus)

Extract the hyperedges with at least one undecided vertex.
"""
function subhg(bip::BooleanInferenceProblem, bs::AbstractBranchingStatus)
    # Extract decided vertices
    decided_v = [i for i in 1:bip.literal_num if readbit(bs.decided_mask, i) == 1]
    # Iterate over all hyperedges and collect the hyperedges that contain at least one undecided vertex
    return [setdiff(bip.he2v[e], decided_v) for e in 1:length(bip.he2v) if bs.undecided_literals[e] > 0], [e for e in 1:length(bip.he2v) if bs.undecided_literals[e] > 0], decided_v
end

function gen_sub_tensor(
    p::BooleanInferenceProblem,
    bs::AbstractBranchingStatus,
    vs::Vector{Int},
    edges::Vector{Int},
    he2v::Vector{Vector{Int}},
    edge_list::Vector{Int}
)
    eincode = EinCode(he2v[edges], vs)
    optcode = optimize_code(eincode, uniformsize(eincode, 2), GreedyMethod())

    sub_tensors = optcode([vec_to_tensor(
        slice_tensor(p.tensors[e], bs.decided_mask, bs.config, p.he2v[e])
    ) for e in edge_list[edges]]...)

    return sub_tensors
end

function hyperedge_to_sparse(he2v::Vector{Vector{Int}})
    I = Int[]
    J = Int[]
    for i in 1:length(he2v)
        for e in 1:length(he2v[i])
            push!(I, he2v[i][e])
            push!(J, i)
        end
    end
    return sparse(I, J, ones(length(I)))
end
