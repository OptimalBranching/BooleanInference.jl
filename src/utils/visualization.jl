using GraphMakie
using CairoMakie: Figure, Axis, save, hidespines!, hidedecorations!, DataAspect, Point2f
using NetworkLayout: SFDP, Spring, Stress, Spectral

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
        node_labels[i] = "v$i"
    end
    for i in 1:n_tensors
        node_labels[n_vars + i] = "t$i"
    end

    return g, node_labels
end

function to_graph(problem::TNProblem)
    bg = problem.static
    g, labels = to_graph(bg)

    n_vars = length(bg.vars)
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

function visualize_problem(problem::TNProblem, file_name::String; 
                            layout_algorithm::Symbol=:stress,
                            nlabels_fontsize::Real=8,
                            show_labels::Bool=true,
                            figure_size::Tuple{Int,Int}=(1200, 1200),
                            layout_kwargs...)
    g, labels, colors = to_graph(problem)
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
                   nlabels_fontsize=nlabels_fontsize)
    
    # Save the figure (Makie handles format automatically based on extension)
    save(file_name, fig)
    return nothing
end