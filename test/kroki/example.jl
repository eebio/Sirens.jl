function example_problem()
    atmosphere = TimeIndependentComponent("Atmosphere", identity, 0.0)
    ocean = TimeIndependentComponent("Ocean", identity, 0.0)
    biosphere = TimeIndependentComponent("Biosphere", identity, 0.0)

    heat = Connector(
        inputs = ["Atmosphere.temperature", "Ocean.surface_temperature"],
        outputs = ["Biosphere.temperature"],
        func = (air, sea) -> (air + sea) / 2
    )
    feedback = ImplicitConnector(
        inputs = ["Biosphere.temperature"],
        outputs = ["Ocean.albedo"]
    )

    return MermaidProblem(
        components = [atmosphere, ocean, biosphere],
        connectors = [heat, feedback],
        tspan = (0.0, 10.0),
        timescales = [1.0, 0.1, 1.0]
    )
end
