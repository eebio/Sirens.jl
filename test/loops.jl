@testitem "loops" begin
    comp1 = TimeIndependentComponent("comp", x -> x, 1.0)
    comp2 = TimeIndependentComponent("comp2", x -> x, 1.0)

    # Order of applying connections does matter here, but no loops
    conn1 = Connector(inputs=["comp.x"], outputs=["comp2.y"])
    conn2 = Connector(inputs=["comp.y"], outputs=["comp2.y"])
    conn3 = Connector(inputs=["comp.z"], outputs=["comp.x"])

    using Logging
    @test_logs min_level=Logging.Warn SirenProblem(components=[comp1, comp2], connectors=[conn1, conn2, conn3], tspan=(0.0, 1.0))

    # Add a loop (x -> 2.y -> z -> x)
    conn4 = Connector(inputs=["comp2.y"], outputs=["comp.z"])
    @test_warn "Algebraic loop" SirenProblem(components=[comp1, comp2], connectors=[conn1, conn2, conn3, conn4], tspan=(0.0, 1.0))

    # Implicit connectors can create loops
    conn5 = ImplicitConnector(inputs=["comp2.y"], outputs=["comp.z"])
    @test_warn "Algebraic loop" SirenProblem(components=[comp1, comp2], connectors=[conn1, conn2, conn3, conn5], tspan=(0.0, 1.0))
end

@testitem "implicit connector doesn't change simulation" begin
    using OrdinaryDiffEq
    using OrdinaryDiffEqLowOrderRK

    function f1!(du, u, p, t)
        x, y = u
        du[1] = 1 - y # y is connected by an implicit connector, so is always 0.5
        du[2] = 0
    end
    function f2!(du, u, p, t)
        du[1] = 0
        du[2] = 0
    end
    tspan = (0.0, 10.0)
    prob1 = ODEProblem(f1!, [1.0, 0.5], tspan)
    prob2 = ODEProblem(f2!, [1000.0, 1000.0], tspan)
    c1 = DEComponent(
        prob1, Tsit5();
        name="comp1",
        state_names=OrderedDict("x" => 1, "y" => 2)
    )

    c2 = DEComponent(
        prob2, Tsit5();
        name="comp2",
        state_names=OrderedDict("x" => 1, "y" => 2)
    )

    conn = ImplicitConnector(
        inputs=["comp2.y"],
        outputs=["comp1.y"]
    )

    sp = SirenProblem(components=[c1, c2], connectors=[conn], tspan=(0.0, 1.0))
    sol = solve(sp, MinimumTimeStepper())

    @test all(sol["comp1.y"] .== 0.5)
    @test sol["comp1.x"][end] > sol["comp1.x"][1]
end
