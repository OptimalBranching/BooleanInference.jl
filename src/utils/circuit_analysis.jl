struct TensorNetworkInfo
    n_vars::Int
    t2v::Vector{Vector{Int}}
    tensor_data::Vector{Vector{Tropical{Float64}}}
    tensor_depths::Vector{Int}
    tensor_fanin::Vector{Vector{Int}}
    tensor_fanout::Vector{Vector{Int}}
end

function setup_from_tn_info(tn_info::TensorNetworkInfo)::BipartiteGraph
    return setup_problem(
        tn_info.n_vars,
        tn_info.t2v,
        tn_info.tensor_data;
        tensor_depths=tn_info.tensor_depths,
        tensor_fanin=tn_info.tensor_fanin,
        tensor_fanout=tn_info.tensor_fanout
    )
end

function tensor_network_info(tn::GenericTensorNetwork, sat::CircuitSAT)
    t2v = getixsv(tn.code)
    tensors = GenericTensorNetworks.generate_tensors(Tropical(1.0), tn)
    # Merge vec + replace to avoid intermediate allocation
    tensor_data = [replace(vec(t), Tropical(1.0) => zero(Tropical{Float64})) for t in tensors]

    circuit_info = compute_circuit_info(sat)
    tensor_info = map_tensor_to_circuit_info(tn, circuit_info, sat)

    return TensorNetworkInfo(
        length(sat.symbols),
        t2v,
        tensor_data,
        tensor_info.depths,
        tensor_info.fanin,
        tensor_info.fanout,
    )
end

function tensor_network_info(sat::CircuitSAT; kwargs...)
    tn = GenericTensorNetwork(sat; kwargs...)
    return tensor_network_info(tn, sat)
end

function compute_circuit_info(sat::ConstraintSatisfactionProblem)
    circuit = sat.circuit
    n_exprs = length(circuit.exprs)

    symbols = [circuit.exprs[i].expr.head for i in 1:n_exprs]

    var_to_producer = Dict{Symbol, Int}()
    for (i, expr) in enumerate(circuit.exprs)
        if expr.expr.head != :var
            for v in expr.outputs
                var_to_producer[v] = i
            end
        end
    end

    var_to_consumers = Dict{Symbol, Vector{Int}}()
    for v in sat.symbols
        var_to_consumers[v] = Int[]
    end

    for (i, expr) in enumerate(circuit.exprs)
        if expr.expr.head == :var
            for v in expr.outputs
                if !haskey(var_to_consumers, v)
                    var_to_consumers[v] = Int[]
                end
                push!(var_to_consumers[v], i)
            end
        else
            for arg in expr.expr.args
                if arg isa BooleanExpr && arg.head == :var
                    var = arg.var
                    if !haskey(var_to_consumers, var)
                        var_to_consumers[var] = Int[]
                    end
                    push!(var_to_consumers[var], i)
                end
            end
        end
    end

    depths = zeros(Int, n_exprs)

    function compute_depth(expr_idx::Int)
        if depths[expr_idx] > 0
            return depths[expr_idx]
        end

        expr = circuit.exprs[expr_idx]
        symbol = expr.expr.head

        if symbol == :var
            depths[expr_idx] = 1
            return 1
        end

        max_consumer_depth = 0
        for v in expr.outputs
            for consumer_idx in var_to_consumers[v]
                consumer_depth = compute_depth(consumer_idx)
                max_consumer_depth = max(max_consumer_depth, consumer_depth)
            end
        end

        depths[expr_idx] = max_consumer_depth + 1
        return depths[expr_idx]
    end

    for i in 1:n_exprs
        compute_depth(i)
    end

    fanin = Vector{Vector{Symbol}}(undef, n_exprs)
    fanout = Vector{Vector{Symbol}}(undef, n_exprs)

    for i in 1:n_exprs
        expr = circuit.exprs[i]
        symbol = expr.expr.head

        output_vars = expr.outputs

        if symbol == :var
            fanin[i] = collect(output_vars)
            constraint_value = expr.expr.var
            fanout[i] = [constraint_value]
            
        else
            input_vars = Symbol[]
            for arg in expr.expr.args
                if arg isa BooleanExpr && arg.head == :var
                    push!(input_vars, arg.var)
                end
            end

            fanin[i] = input_vars
            fanout[i] = output_vars
        end
    end

    return (depths=depths, fanin=fanin, fanout=fanout, symbols=symbols)
end

function map_tensor_to_circuit_info(tn, circuit_info, sat)
    t2v = getixsv(tn.code)
    n_tensors = length(t2v)
    tensor_depths = zeros(Int, n_tensors)
    tensor_fanin = Vector{Vector{Int}}(undef, n_tensors)
    tensor_fanout = Vector{Vector{Int}}(undef, n_tensors)

    symbol_to_id = Dict{Symbol, Int}()
    for (i, symbol) in enumerate(sat.symbols)
        symbol_to_id[symbol] = i
    end

    for i in 1:min(n_tensors, length(circuit_info.depths))
        tensor_depths[i] = circuit_info.depths[i]

        fanin_ids = Int[]
        for sym in circuit_info.fanin[i]
            if haskey(symbol_to_id, sym)
                push!(fanin_ids, symbol_to_id[sym])
            end
        end
        tensor_fanin[i] = fanin_ids

        fanout_ids = Int[]
        for sym in circuit_info.fanout[i]
            if haskey(symbol_to_id, sym)
                push!(fanout_ids, symbol_to_id[sym])
            end
        end
        tensor_fanout[i] = fanout_ids
    end

    return (depths=tensor_depths, fanin=tensor_fanin, fanout=tensor_fanout)
end
