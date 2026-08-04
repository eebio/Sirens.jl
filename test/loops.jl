@testitem "loops" begin
    comp1 = TimeIndependentComponent("comp", x -> x, 1.0)
    comp2 = TimeIndependentComponent("comp2", x -> x, 1.0)

    # Order of applying connections does matter here, but no loops
    conn1 = Connector(inputs=["comp.x"], outputs=["comp2.y"])
    conn2 = Connector(inputs=["comp.y"], outputs=["comp2.y"])
    conn3 = Connector(inputs=["comp.z"], outputs=["comp.x"])

    using Logging
    @test_logs min_level=Logging.Warn MermaidProblem(components=[comp1, comp2], connectors=[conn1, conn2, conn3], tspan=(0.0, 1.0))

    # Add a loop (x -> 2.y -> z -> x)
    conn4 = Connector(inputs=["comp2.y"], outputs=["comp.z"])
    @test_warn "Algebraic loop" MermaidProblem(components=[comp1, comp2], connectors=[conn1, conn2, conn3, conn4], tspan=(0.0, 1.0))
end
