struct Variable
    deg::Int
end

function Base.show(io::IO, v::Variable)
    print(io, "Variable(deg=$(v.deg))")
end

struct BoolTensor
    var_axes::Vector{Int}
    tensor::Vector{Tropical{Float64}}
end

function Base.show(io::IO, f::BoolTensor)
    print(io, "BoolTensor(vars=[$(join(f.var_axes, ", "))], size=$(length(f.tensor)))")
end

struct BipartiteGraph
    vars::Vector{Variable}
    tensors::Vector{BoolTensor}
    v2t::Vector{Vector{Int}}
end

function Base.show(io::IO, tn::BipartiteGraph)
    print(io, "BipartiteGraph(vars=$(length(tn.vars)), tensors=$(length(tn.tensors)))")
end

function Base.show(io::IO, ::MIME"text/plain", tn::BipartiteGraph)
    println(io, "BipartiteGraph:")
    println(io, "  variables: $(length(tn.vars))")
    println(io, "  tensors: $(length(tn.tensors))")
    println(io, "  variable-tensor incidence: $(length(tn.v2t))")
end

function setup_problem(var_num::Int,
                       tensors_to_vars::Vector{Vector{Int}},
                       tensor_data::Vector{Vector{Tropical{Float64}}})
    F = length(tensors_to_vars)
    tensors = Vector{BoolTensor}(undef, F)
    vars_to_tensors = [Int[] for _ in 1:var_num]
    for i in 1:F
        var_axes = tensors_to_vars[i]
        @assert length(tensor_data[i]) == 1 << length(var_axes)
        tensors[i] = BoolTensor(var_axes, tensor_data[i])
        for v in var_axes
            push!(vars_to_tensors[v], i)
        end
    end

    vars = Vector{Variable}(undef, var_num)
    for i in 1:var_num
        vars[i] = Variable(length(vars_to_tensors[i]))
    end
    return BipartiteGraph(vars, tensors, vars_to_tensors)
end

function setup_from_tensor_network(tn)
    t2v = getixsv(tn.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), tn)
    new_tensors = [replace(vec(t), Tropical(1.0) => zero(Tropical{Float64})) for t in tensors]
    return setup_problem(length(tn.problem.symbols), t2v, new_tensors)
end
