# System diagrams

A [`MermaidProblem`](@ref) can be visualised with the optional
[Kroki.jl](https://bauglir.github.io/Kroki.jl/stable/) extension.
The extension uses Kroki's Graphviz renderer.

Install Kroki and load both packages:

```text
pkg> add Kroki
```

```@example system_diagrams
using Mermaid
using Kroki

producer = TimeIndependentComponent("producer", identity, 1.0)
consumer = TimeIndependentComponent("consumer", identity, 0.0)

connection = Connector(
    inputs = ["producer.#state"],
    outputs = ["consumer.#state"],
)

problem = MermaidProblem(
    components = [producer, consumer],
    connectors = [connection],
    tspan = (0.0, 1.0),
)

systemdiagram(problem)
```

By default, connected variables are shown as ports in a left-to-right diagram.
A component-level, top-to-bottom view can be created with:

```julia
systemdiagram(problem; detail = :components, direction = :TB)
```

`detail` accepts `:ports` or `:components`; `direction` accepts `:LR` or `:TB`.

Creating a diagram only reads the problem definition. It does not initialise components,
execute connector functions, or solve the problem. Displaying the returned
`Kroki.Diagram` renders it through the endpoint configured by Kroki.jl.
