@testsnippet example_problem begin
    atmosphere = TimeIndependentComponent("Atmosphere", identity, 0.0)
    ocean = TimeIndependentComponent("Ocean", identity, 0.0)
    biosphere = TimeIndependentComponent("Biosphere", identity, 0.0)

    heat = Connector(
        inputs=["Atmosphere.temperature", "Ocean.surface_temperature"],
        outputs=["Biosphere.temperature"],
        func=(air, sea) -> (air + sea) / 2
    )
    feedback = ImplicitConnector(
        inputs=["Biosphere.temperature"],
        outputs=["Ocean.albedo"]
    )

    example_problem = SirenProblem(
        components=[atmosphere, ocean, biosphere],
        connectors=[heat, feedback],
        tspan=(0.0, 10.0),
        timescales=[1.0, 0.1, 1.0]
    )
end

@testitem "Kroki system diagrams" setup = [example_problem] begin
    using Kroki

    extension_module = Base.get_extension(Sirens, :KrokiExt)
    @test !isnothing(extension_module)

    problem = example_problem
    ports = systemdiagram(problem)
    components = systemdiagram(problem; detail = :components, direction = :TB)

    @test ports isa Kroki.Diagram
    @test ports.type == :graphviz
    @test ports.specification == systemdiagram(problem).specification
    @test startswith(ports.specification, "digraph SirenSystem {\n")
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
    unresolved = SirenProblem(
        components = [unusual],
        connectors = [Connector(
            inputs = ["Missing.value"], outputs = ["A \" B & C.value"])],
        tspan = (0.0, 1.0)
    )
    unresolved_source = systemdiagram(unresolved).specification
    @test occursin("A \\\" B & C", unresolved_source)
    @test occursin("unresolved: Missing.value", unresolved_source)
    @test occursin("port_1 [label=\"unresolved: Missing.value\"", unresolved_source)

    unresolved_source = systemdiagram(unresolved; detail = :components).specification
    @test occursin("unresolved: Missing\"", unresolved_source)

    opaque = TimeIndependentComponent("Opaque", _ -> error("must not initialize"), 0.0)
    opaque_problem = SirenProblem(
        components = [opaque], connectors = [], tspan = (0.0, 1.0))
    @test_nowarn systemdiagram(opaque_problem)
end
