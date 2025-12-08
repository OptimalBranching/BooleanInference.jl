function to_graph(bg::BipartiteGraph)
    n_vars = length(bg.vars)
    n_tensors = length(bg.tensors)
    n_nodes = n_vars + n_tensors

    g = SimpleGraph(n_nodes)

    for (var_id, tensor_ids) in enumerate(bg.v2t)
        for tensor_id in tensor_ids
            add_edge!(g, var_id, n_vars + tensor_id)
        end
    end

    node_labels = Dict{Int, String}()
    for i in 1:n_vars
        node_labels[i] = "$i"
    end
    for i in 1:n_tensors
        node_labels[n_vars + i] = "t$(i)$(bg.tensor_symbols[i])"
    end

    return g, node_labels
end

function to_graph(problem::TNProblem, tensor_indices::Union{Nothing, Vector{Int}}=nothing)
    bg = problem.static
    n_vars = length(bg.vars)
    n_tensors = length(bg.tensors)

    # If tensor_indices is specified, filter tensors
    if !isnothing(tensor_indices)
        # Validate tensor indices
        for idx in tensor_indices
            if idx < 1 || idx > n_tensors
                error("Invalid tensor index: $idx. Must be in range 1:$n_tensors")
            end
        end

        # Create filtered bipartite graph
        # Find which variables are connected to the selected tensors
        relevant_vars = Set{Int}()
        for var_id in 1:n_vars
            tensor_ids = bg.v2t[var_id]
            if any(tid in tensor_indices for tid in tensor_ids)
                push!(relevant_vars, var_id)
            end
        end

        relevant_vars = sort(collect(relevant_vars))
        n_relevant_vars = length(relevant_vars)
        n_selected_tensors = length(tensor_indices)
        n_nodes = n_relevant_vars + n_selected_tensors

        g = SimpleGraph(n_nodes)

        # Create mappings
        var_to_node = Dict(var_id => i for (i, var_id) in enumerate(relevant_vars))
        tensor_to_node = Dict(tid => n_relevant_vars + i for (i, tid) in enumerate(tensor_indices))

        # Add edges
        for var_id in relevant_vars
            for tensor_id in bg.v2t[var_id]
                if tensor_id in tensor_indices
                    add_edge!(g, var_to_node[var_id], tensor_to_node[tensor_id])
                end
            end
        end

        # Create labels
        node_labels = Dict{Int, String}()
        for (i, var_id) in enumerate(relevant_vars)
            node_labels[i] = "$var_id"
        end
        for (i, tensor_id) in enumerate(tensor_indices)
            node_labels[n_relevant_vars + i] = "t$(tensor_id)$(bg.tensor_symbols[tensor_id])"
        end

        # Create colors
        node_colors = Dict{Int, Int}()
        for (i, var_id) in enumerate(relevant_vars)
            dom = problem.doms[var_id]
            if is_fixed(dom)
                node_colors[i] = has1(dom) ? 2 : 1
            else
                node_colors[i] = 3
            end
        end
        for i in 1:n_selected_tensors
            node_colors[n_relevant_vars + i] = 4
        end

        return g, node_labels, node_colors
    else
        # Original behavior: show all tensors
        g, labels = to_graph(bg)

        node_colors = Dict{Int, Int}()

        for i in 1:n_vars
            dom = problem.doms[i]
            if is_fixed(dom)
                node_colors[i] = has1(dom) ? 2 : 1
            else
                node_colors[i] = 3
            end
        end

        for i in 1:length(bg.tensors)
            node_colors[n_vars + i] = 4
        end

        return g, labels, node_colors
    end
end


function get_highest_degree_variables(problem::TNProblem, n::Int=1)
    bg = problem.static
    n_vars = length(bg.vars)

    # Calculate degree for each variable
    degrees = [(var_id, length(bg.v2t[var_id])) for var_id in 1:n_vars]

    # Sort by degree (descending)
    sort!(degrees, by=x->x[2], rev=true)

    # Return top n variable indices
    return [degrees[i][1] for i in 1:min(n, length(degrees))]
end


function get_tensors_containing_variables(problem::TNProblem, var_indices::Vector{Int})
    bg = problem.static
    tensor_set = Set{Int}()

    for var_id in var_indices
        for tensor_id in bg.v2t[var_id]
            push!(tensor_set, tensor_id)
        end
    end

    return sort(collect(tensor_set))
end


function visualize_highest_degree_vars(problem::TNProblem, file_name::String;
                                        n_vars::Int=1,
                                        layout_algorithm::Symbol=:stress,
                                        nlabels_fontsize::Real=8,
                                        node_size::Real=20,
                                        show_labels::Bool=true,
                                        figure_size::Tuple{Int,Int}=(1200, 1200),
                                        layout_kwargs...)
    # Get highest degree variables
    high_degree_vars = get_highest_degree_variables(problem, n_vars)

    # Get tensors containing these variables
    tensor_indices = get_tensors_containing_variables(problem, high_degree_vars)

    # Print info
    println("Highest degree variables: $high_degree_vars")
    for var_id in high_degree_vars
        degree = length(problem.static.v2t[var_id])
        println("  Variable $var_id: degree = $degree")
    end
    println("Tensors to visualize ($(length(tensor_indices))): $tensor_indices")

    # Visualize
    visualize_problem(problem, file_name;
                      tensor_indices=tensor_indices,
                      layout_algorithm=layout_algorithm,
                      nlabels_fontsize=nlabels_fontsize,
                      node_size=node_size,
                      show_labels=show_labels,
                      figure_size=figure_size,
                      layout_kwargs...)
end

function visualize_problem(problem::TNProblem, file_name::String;
                            tensor_indices::Union{Nothing, Vector{Int}}=nothing,
                            layout_algorithm::Symbol=:stress,
                            nlabels_fontsize::Real=8,
                            node_size::Real=20,
                            show_labels::Bool=true,
                            figure_size::Tuple{Int,Int}=(1200, 1200),
                            layout_kwargs...)
    g, labels, colors = to_graph(problem, tensor_indices)
    color_list = [colorant"red", colorant"green", colorant"blue", colorant"gray"]
    node_colors = [color_list[colors[i]] for i in 1:nv(g)]
    node_labels = [labels[i] for i in 1:nv(g)]

    n_vars = length(problem.static.vars)
    n_tensors = length(problem.static.tensors)
    n_nodes = nv(g)
    
    # Create figure and plot using GraphMakie
    # Use larger figure size to give more space between nodes
    fig = Figure(size=figure_size)
    ax = Axis(fig[1, 1], 
              aspect=DataAspect(),  # Maintain aspect ratio
              xautolimitmargin=(0.15, 0.15),
              yautolimitmargin=(0.15, 0.15))
    hidespines!(ax)
    hidedecorations!(ax)

    # Select layout algorithm
    layout = if layout_algorithm == :bipartite
        # Special layout for bipartite graphs: place vars on left, tensors on right
        # Use initial positions to separate the two groups
        initialpos = Dict{Int, Point2f}()
        # Place variable nodes on the left
        for i in 1:n_vars
            y_pos = (i - 1) / max(1, n_vars - 1) * 2 - 1  # Normalize to [-1, 1]
            initialpos[i] = Point2f(-1.5, y_pos)
        end
        # Place tensor nodes on the right
        for i in 1:n_tensors
            y_pos = (i - 1) / max(1, n_tensors - 1) * 2 - 1
            initialpos[n_vars + i] = Point2f(1.5, y_pos)
        end
        # Use SFDP with initial positions
        SFDP(Ptype=Float32; tol=0.01, C=0.2, K=1.0, initialpos=initialpos, layout_kwargs...)
    elseif layout_algorithm == :spring
        Spring(Ptype=Float32; C=2.0, iterations=100, layout_kwargs...)
    elseif layout_algorithm == :sfdp
        SFDP(Ptype=Float32; tol=0.01, C=0.2, K=1.0, iterations=100, layout_kwargs...)
    elseif layout_algorithm == :stress
        Stress(Ptype=Float32; iterations=500, layout_kwargs...)
    elseif layout_algorithm == :spectral
        Spectral(Ptype=Float32, dim=2)
    else
        error("Unknown layout algorithm: $layout_algorithm. Use :bipartite, :spring, :sfdp, :stress, or :spectral")
    end
    
    p = graphplot!(ax, g, layout=layout,
                   nlabels=show_labels ? node_labels : nothing,
                   node_color=node_colors,
                   node_size=node_size,
                   nlabels_fontsize=nlabels_fontsize)
    
    # Save the figure (Makie handles format automatically based on extension)
    save(file_name, fig)
    return nothing
end