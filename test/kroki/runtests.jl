using Test
using Kroki
using Mermaid

include("example.jl")

@testset "Kroki system diagrams" begin
    extension_module = Base.get_extension(Mermaid, :KrokiExt)
    @test !isnothing(extension_module)

    problem = example_problem()
    ports = systemdiagram(problem)
    components = systemdiagram(problem; detail = :components, direction = :TB)

    @test ports isa Kroki.Diagram
    @test ports.type == :graphviz
    @test ports.specification == systemdiagram(problem).specification
    @test startswith(ports.specification, "digraph MermaidSystem {\n")
    @test occursin("graph [rankdir=LR, bgcolor=\"white\"", ports.specification)
    @test occursin("subgraph cluster_component_1", ports.specification)
    @test occursin("connector_1 [label=\"Connector 1\\ntransform\"", ports.specification)
    @test occursin("connector_2 [label=\"Implicit 2\"", ports.specification)
    @test occursin("connector_2 -> port_4 [label=\"output\", style=dashed]",
        ports.specification)
    @test endswith(ports.specification, "}\n")

    @test occursin("graph [rankdir=TB", components.specification)
    @test occursin("Ocean\\ntimescale = 0.1", components.specification)
    @test occursin("component_3 -> connector_2 [label=\"temperature\", style=dashed]",
        components.specification)
    @test occursin("connector_2 -> component_2 [label=\"albedo\", style=dashed]",
        components.specification)

    @test_throws ArgumentError systemdiagram(problem; detail = :state)
    @test_throws ArgumentError systemdiagram(problem; direction = :diagonal)

    unusual = TimeIndependentComponent("A \" B & C", identity, 0.0)
    unresolved = MermaidProblem(
        components = [unusual],
        connectors = [Connector(
            inputs = ["Missing.value"], outputs = ["A \" B & C.value"])],
        tspan = (0.0, 1.0)
    )
    unresolved_source = systemdiagram(unresolved).specification
    @test occursin("A \\\" B & C", unresolved_source)
    @test occursin("unresolved: Missing.value", unresolved_source)
    @test occursin("port_1 [label=\"unresolved: Missing.value\"", unresolved_source)

    opaque = TimeIndependentComponent("Opaque", _ -> error("must not initialize"), 0.0)
    opaque_problem = MermaidProblem(
        components = [opaque], connectors = [], tspan = (0.0, 1.0))
    @test_nowarn systemdiagram(opaque_problem)
end
