module KrokiExt

using Kroki
using Sirens

import Sirens: systemdiagram

# Options and Graphviz styles

const _DETAILS = (:components, :ports)
const _DIRECTIONS = (:LR, :TB)

const _COMPONENT_STYLE = "shape=box, style=\"rounded,filled\", fillcolor=\"#e8f1fb\", " *
                         "color=\"#3973ac\", fontcolor=\"#14283d\""
const _PORT_STYLE = "shape=box, style=filled, fillcolor=\"#f5f8fc\", color=\"#3973ac\", fontcolor=\"#14283d\""
const _CONNECTOR_STYLE = "shape=diamond, style=filled, fillcolor=\"#fff4d6\", color=\"#b47b00\", fontcolor=\"#3d2a00\""
const _IMPLICIT_STYLE = "shape=diamond, style=\"filled,dashed\", fillcolor=\"#f2eafb\", " *
                        "color=\"#7950a3\", fontcolor=\"#2f1d41\""
const _UNRESOLVED_STYLE = "shape=box, style=\"filled,dashed\", fillcolor=\"#fdeaea\", " *
                          "color=\"#b23b3b\", fontcolor=\"#4a1717\""

function _validate_option(value::Symbol, supported, name)
    value in supported && return value
    choices = join((repr(choice) for choice in supported), ", ")
    throw(ArgumentError("unsupported $name=$(repr(value)); expected one of $choices"))
end

# Siren topology inspection
# Diagram generation is structural: never initialize components or execute connectors.

_component_name(component) = string(name(component))

# First appearance defines stable port IDs without sorting user-authored names.
function _ordered_endpoints(problem::SirenProblem)
    ordered = ConnectedVariable[]
    seen = Set{String}()
    for connector in problem.connectors
        for collection in (connector.inputs, connector.outputs)
            for endpoint in collection
                key = fullname(endpoint)
                if !(key in seen)
                    push!(seen, key)
                    push!(ordered, endpoint)
                end
            end
        end
    end
    return ordered
end

function _unresolved_components(problem::SirenProblem, endpoints)
    known = Set(_component_name(component) for component in problem.components)
    unresolved = String[]
    seen = Set{String}()
    for endpoint in endpoints
        component = string(endpoint.component)
        if !(component in known) && !(component in seen)
            push!(seen, component)
            push!(unresolved, component)
        end
    end
    return unresolved
end

# Connectors are explicit nodes so fan-in and fan-out retain their many-to-many meaning.
function _connector_label(connector, index)
    if connector isa ImplicitConnector
        return "Implicit $index"
    elseif connector isa Connector && !isnothing(connector.func)
        return "Connector $index\ntransform"
    end
    return "Connector $index"
end

function _connector_style(connector)
    connector isa ImplicitConnector ? _IMPLICIT_STYLE : _CONNECTOR_STYLE
end

function _port_label(endpoint)
    duplicated = isnothing(endpoint.duplicatedindex) ?
                 "" : "[$(endpoint.duplicatedindex)]."
    index = isnothing(endpoint.variableindex) ? "" : "[$(endpoint.variableindex)]"
    return "$duplicated$(endpoint.variable)$index"
end

# DOT writing primitives

function _dot_label(value)
    text = replace(string(value), '\\' => "\\\\")
    text = replace(text, '"' => "\\\"")
    return replace(text, '\n' => "\\n")
end

function _write_node!(io, id, label, style)
    println(io, "    $id [label=\"$(_dot_label(label))\", $style]")
end

function _write_edge!(io, source, connector, target, label)
    style = connector isa ImplicitConnector ? ", style=dashed" : ""
    println(io, "    $source -> $target [label=\"$(_dot_label(label))\"$style]")
end

function _write_connector!(io, connector, index)
    id = "connector_$index"
    _write_node!(io, id, _connector_label(connector, index), _connector_style(connector))
    return id
end

# Diagram views

function _write_component_view!(io, problem, component_ids, unresolved, unresolved_ids)
    for (index, component) in enumerate(problem.components)
        component_name = _component_name(component)
        label = component_name
        timescale = problem.timescales[index]
        timescale == 1.0 || (label *= "\ntimescale = $timescale")
        _write_node!(io, component_ids[component_name], label, _COMPONENT_STYLE)
    end
    for component in unresolved
        _write_node!(io, unresolved_ids[component], "unresolved: $component", _UNRESOLVED_STYLE)
    end

    for (index, connector) in enumerate(problem.connectors)
        connector_id = _write_connector!(io, connector, index)
        for endpoint in connector.inputs
            component = string(endpoint.component)
            source = get(component_ids, component) do
                unresolved_ids[component]
            end
            _write_edge!(io, source, connector, connector_id, _port_label(endpoint))
        end
        for endpoint in connector.outputs
            component = string(endpoint.component)
            target = get(component_ids, component) do
                unresolved_ids[component]
            end
            _write_edge!(io, connector_id, connector, target, _port_label(endpoint))
        end
    end
end

function _write_port_view!(io, problem, endpoints, component_ids)
    port_ids = Dict{String, String}(
        fullname(endpoint) => "port_$index" for (index, endpoint) in enumerate(endpoints))

    for component in problem.components
        component_name = _component_name(component)
        component_ports = filter(endpoint -> endpoint.component == component_name, endpoints)
        if isempty(component_ports)
            _write_node!(io, component_ids[component_name], component_name, _COMPONENT_STYLE)
            continue
        end
        println(io, "    subgraph cluster_$(component_ids[component_name]) {")
        println(io, "        label=\"$(_dot_label(component_name))\"")
        println(io, "        color=\"#3973ac\"")
        println(io, "        style=rounded")
        for endpoint in component_ports
            port_id = port_ids[fullname(endpoint)]
            println(io,
                "        $port_id [label=\"$(_dot_label(_port_label(endpoint)))\", $(_PORT_STYLE)]")
        end
        println(io, "    }")
    end

    for endpoint in endpoints
        haskey(component_ids, string(endpoint.component)) && continue
        port_id = port_ids[fullname(endpoint)]
        _write_node!(io, port_id, "unresolved: $(fullname(endpoint))", _UNRESOLVED_STYLE)
    end

    for (index, connector) in enumerate(problem.connectors)
        connector_id = _write_connector!(io, connector, index)
        for endpoint in connector.inputs
            _write_edge!(io, port_ids[fullname(endpoint)], connector, connector_id, "input")
        end
        for endpoint in connector.outputs
            _write_edge!(
                io, connector_id, connector, port_ids[fullname(endpoint)], "output")
        end
    end
end

# Assembly and public API

function _graphviz_source(problem::SirenProblem, detail, direction)
    endpoints = _ordered_endpoints(problem)
    unresolved = _unresolved_components(problem, endpoints)
    # Ordinal IDs make output stable and keep user-authored names confined to escaped labels.
    component_ids = Dict(
        _component_name(component) => "component_$index"
    for (index, component) in enumerate(problem.components))
    unresolved_ids = Dict(
        component => "unresolved_$index" for (index, component) in enumerate(unresolved))

    return sprint() do io
        println(io, "digraph SirenSystem {")
        println(io,
            "    graph [rankdir=$direction, bgcolor=\"white\", fontname=\"Helvetica\"]")
        println(io, "    node [fontname=\"Helvetica\"]")
        println(io, "    edge [fontname=\"Helvetica\"]")
        if detail == :components
            _write_component_view!(io, problem, component_ids, unresolved, unresolved_ids)
        else
            _write_port_view!(io, problem, endpoints, component_ids)
        end
        println(io, "}")
    end
end

function systemdiagram(
        problem::SirenProblem; detail::Symbol = :ports, direction::Symbol = :LR)
    _validate_option(detail, _DETAILS, :detail)
    _validate_option(direction, _DIRECTIONS, :direction)
    return Kroki.Diagram(:graphviz, _graphviz_source(problem, detail, direction))
end

end
