function build_depedency_graph(conns::Vector{AbstractConnector})
    graph = MetaGraph(DiGraph(), ConnectedVariable)

    # Strip indexes from the variable names in the connections
    # It is possible for specific indicies to mean that connections don't loop, but I don't think its that big of a problem if we slightly overreport in this case
    conns = [strip_index(conn) for conn in conns]

    # Add all vertices to the graph
    for conn in conns
        for var in conn.inputs
            add_vertex!(graph, var)
        end
        for var in conn.outputs
            add_vertex!(graph, var)
        end
    end
    # Add edges to the graph based on connections
    for conn in conns
        for input_var in conn.inputs
            for output_var in conn.outputs
                add_edge!(graph, input_var, output_var)
            end
        end
    end
    return graph
end

function report_algebraic_loop(conns::Vector{AbstractConnector})
    graph = build_depedency_graph(conns)
    if is_cyclic(graph)
        cycles = simplecycles(graph)
        str = "Algebraic loop(s) detected in the following connections:\n"
        for cycle in cycles
            str *= "Cycle: "
            for var in cycle
                str *= "$(fullname(graph.vertex_labels[var])) -> "
            end
            str *= "$(fullname(graph.vertex_labels[cycle[1]])) \n"
        end
        @warn str
    end
end
