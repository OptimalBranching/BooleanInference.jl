function readcnf(filename::String)
    f = open(filename)
    vals = split(readline(f))
    tensors = Vector{Vector{Tropical{Float64}}}()
    he2v = Vector{Vector{Int}}()
    for line in eachline(f)
        cl = filter(!iszero, parse.(Int, split(line)))
        tensor, literals = clause2tensors(cl)
        push!(tensors, tensor)
        push!(he2v, literals)
    end
    @assert length(he2v) == parse(Int, vals[4])
    return BooleanInferenceProblem(tensors, he2v, parse(Int, vals[3]))
end

function clause2tensors(clause::Vector{Int})
    tensor = ones(Tropical{Float64}, 2^length(clause))
    literals = Int[]
    sum = 0
    for j in 1:length(clause)
        sum += (1 << (j - 1)) * (sign(clause[j]) == 1 ? 0 : 1)
        push!(literals, abs(clause[j]))
    end
    tensor[sum+1] = Tropical(-Inf)
    return tensor,literals
end

function solvecnf(filename::String; bsconfig::BranchingStrategy = BranchingStrategy(table_solver = TNContractionSolver(), selector = KNeighborSelector(1,1), measure=NumOfVertices()), reducer=NoReducer())
    p = readcnf(filename)
    return solvebip(p; bsconfig, reducer)
end