@testitem "simple ODE" begin
    using OrdinaryDiffEq
    using OrdinaryDiffEqLowOrderRK

    function f!(du, u, p, t)
        x, y = u
        du[1] = x - x * y
        du[2] = -y + x * y
    end

    u0 = [4.0, 2.0]
    tspan = (0.0, 0.1)
    prob = ODEProblem(f!, u0, tspan)
    solODE = solve(prob, Euler(); adaptive = false, dt = 0.002)

    function f1!(du, u, p, t)
        x, y = u
        du[1] = x - x * y
        du[2] = 0
    end
    function f2!(du, u, p, t)
        y, x = u
        du[1] = -y + x * y
        du[2] = 0
    end
    prob1 = ODEProblem(f1!, [u0[1], 2.0], tspan) # TODO Initial value for params is intentionally wrong
    prob2 = ODEProblem(f2!, [u0[2], 4.0], tspan)
    c1 = DEComponent(
        prob1, Euler();
        name = "Prey",
        timestep = 0.002,
        state_names = OrderedDict("prey" => 1, "predator" => 2),
        intkwargs = (:adaptive => false, :dt => 0.002)
    )

    c2 = DEComponent(
        prob2, Euler();
        name = "Predator",
        timestep = 0.002,
        state_names = OrderedDict("predator" => 1, "prey" => 2),
        intkwargs = (:adaptive => false, :dt => 0.002)
    )

    conn1 = Connector(
        inputs = ["Predator.predator"],
        outputs = ["Prey.predator"]
    )
    conn2 = Connector(
        inputs = ["Prey.prey"],
        outputs = ["Predator.prey"]
    )

    mp = MermaidProblem(components = [c1, c2], connectors = [conn1, conn2], tspan = (0.0, 0.1))

    alg = MinimumTimeStepper()
    solMer = solve(mp, alg)

    @test all(solMer.t .≈ solODE.t)
    preyODE = [solODE(t)[1] for t in solMer.t]
    predatorODE = [solODE(t)[2] for t in solMer.t]
    @test all(solMer["Prey.prey"] .≈ preyODE)
    @test all(solMer["Predator.predator"] .≈ predatorODE)

    # If you don't specify algorithm, DE decides for you
    c2 = DEComponent(
        prob2;
        name = "Predator",
        timestep = 0.002,
        state_names = OrderedDict("predator" => 1, "prey" => 2),
        intkwargs = ()
    )
    mp = MermaidProblem(components = [c1, c2], connectors = [conn1, conn2], tspan = (0.0, 10.0))
    solve(mp, alg)
end

@testitem "mtk" begin
    using ModelingToolkit, OrdinaryDiffEq
    using OrdinaryDiffEqLowOrderRK
    using ModelingToolkit: t_nounits as t, D_nounits as D

    @variables x(t) y(t)
    eqs = [D(x) ~ x - x * y
           D(y) ~ -y + x * y]
    @mtkcompile lv = System(eqs, t)
    prob = ODEProblem(lv, [x => 4.0, y => 2.0], (0.0, 0.1))

    solODE = solve(prob, Euler(); adaptive = false, dt = 0.002)

    eqs = [D(x) ~ x - x * y
           D(y) ~ 0]
    @mtkcompile lv1 = System(eqs, t)
    prob = ODEProblem(lv1, [x => 4.0, y => 2.0], (0.0, 0.1))

    c1 = DEComponent(
        prob, Euler();
        name = "Prey",
        timestep = 0.002,
        state_names = OrderedDict("prey" => x, "predator" => y),
        intkwargs = (:adaptive => false, :dt => 0.002)
    )

    eqs = [D(x) ~ 0
           D(y) ~ -y + x * y]
    @mtkcompile lv2 = System(eqs, t)
    prob = ODEProblem(lv2, [x => 4.0, y => 2.0], (0.0, 0.1))

    c2 = DEComponent(
        prob, Euler();
        name = "Predator",
        timestep = 0.002,
        state_names = OrderedDict("prey" => x, "predator" => y),
        intkwargs = (:adaptive => false, :dt => 0.002)
    )

    conn1 = Connector(
        inputs = ["Predator.predator"],
        outputs = ["Prey.predator"]
    )
    conn2 = Connector(
        inputs = ["Prey.prey"],
        outputs = ["Predator.prey"]
    )

    mp = MermaidProblem(components = [c1, c2], connectors = [conn1, conn2], tspan = (0.0, 0.1))

    using CommonSolve
    alg = MinimumTimeStepper()
    # Ensure the code is compiled
    solMer = solve(mp, alg)

    preyODE = [solODE(t; idxs = x) for t in solMer.t]
    predatorODE = [solODE(t; idxs = y) for t in solMer.t]

    @test all(solMer.t .≈ solODE.t)
    @test all(solMer["Prey.prey"] .≈ preyODE)
    @test all(solMer["Predator.predator"] .≈ predatorODE)
end

@testitem "state control" begin
    using OrdinaryDiffEq

    function f!(du, u, p, t)
        x, y = u
        du[1] = x - x * y
        du[2] = -y + x * y
    end

    u0 = [4.0, 2.0]
    tspan = (0.0, 10.0)
    prob = ODEProblem(f!, u0, tspan)

    c1 = DEComponent(
        prob, Rodas5P();
        name = "Lotka-Volterra",
        timestep = 0.002,
        state_names = OrderedDict("prey" => 1, "predator" => 2)
    )

    conn1 = Connector(
        inputs = ["Lotka-Volterra.predator"],
        outputs = ["other.predator"]
    )
    conn2 = Connector(
        inputs = ["other.prey"],
        outputs = ["Lotka-Volterra.prey"]
    )
    integrator = init(c1)

    @test issetequal(variables(integrator), ["prey", "predator", "#time", "#integrator", "#state"])

    # Check initial state
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.prey")) == 4.0
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.predator")) == 2.0
    @test getstate(integrator) == [4.0, 2.0]

    # Check setting state
    setstate!(integrator, ConnectedVariable("Lotka-Volterra.prey"), 5.0)
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.prey")) == 5.0
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.predator")) == 2.0
    @test getstate(integrator) == [5.0, 2.0]
    setstate!(integrator, [1.0, 1.0])
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.prey")) == 1.0
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.predator")) == 1.0
    @test getstate(integrator) == [1.0, 1.0]
    setstate!(integrator, ConnectedVariable("Lotka-Volterra.predator"), 3.0)
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.prey")) == 1.0
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.predator")) == 3.0
    @test getstate(integrator) == [1.0, 3.0]

    # Check time control
    @test gettime(integrator) == 0.0
    step!(integrator)
    @test gettime(integrator) == 0.002
    settime!(integrator, 1.0)
    @test gettime(integrator) == 1.0
    step!(integrator)
    @test gettime(integrator) == 1.002

    # Step means the state has changed
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.prey")) ≠ 1.0
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.predator")) ≠ 1.0
    @test getstate(integrator) ≠ [1.0, 1.0]

    # Check we can get and set the whole integrator
    int2 = getstate(integrator, ConnectedVariable("Lotka-Volterra.#integrator"); copy=true)
    @test int2.u == getstate(integrator)
    step!(integrator)
    @test getstate(integrator) ≠ int2.u
    setstate!(integrator, ConnectedVariable("Lotka-Volterra.#integrator"), int2)
    @test getstate(integrator) == int2.u

    # Test special variable #state
    @test "#state" in variables(integrator)
    state_via_special = getstate(integrator, ConnectedVariable("Lotka-Volterra.#state"))
    @test state_via_special == int2.u
    @test state_via_special isa Vector
    new_state = [2.5, 1.5]
    setstate!(integrator, ConnectedVariable("Lotka-Volterra.#state"), new_state)
    @test getstate(integrator, ConnectedVariable("Lotka-Volterra.#state")) == new_state
    @test getstate(integrator) == new_state
end
