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
    solODE = solve(prob, Euler(); adaptive=false, dt=0.002)

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
        name="Prey",
        timestep=0.002,
        state_names=OrderedDict("prey" => 1, "predator" => 2),
        intkwargs=(; adaptive=false, dt=0.002)
    )

    c2 = DEComponent(
        prob2, Euler();
        name="Predator",
        timestep=0.002,
        state_names=OrderedDict("predator" => 1, "prey" => 2),
        intkwargs=(; adaptive=false, dt=0.002)
    )

    conn1 = Connector(
        inputs=["Predator.predator"],
        outputs=["Prey.predator"]
    )
    conn2 = Connector(
        inputs=["Prey.prey"],
        outputs=["Predator.prey"]
    )

    sp = SirenProblem(components=[c1, c2], connectors=[conn1, conn2], tspan=(0.0, 0.1))

    alg = MinimumTimeStepper()
    sirenSol = solve(sp, alg)

    @test all(sirenSol.t .≈ solODE.t)
    preyODE = [solODE(t)[1] for t in sirenSol.t]
    predatorODE = [solODE(t)[2] for t in sirenSol.t]
    @test all(sirenSol["Prey.prey"] .≈ preyODE)
    @test all(sirenSol["Predator.predator"] .≈ predatorODE)

    # If you don't specify algorithm, DE decides for you
    c2 = DEComponent(
        prob2;
        name="Predator",
        timestep=0.002,
        state_names=OrderedDict("predator" => 1, "prey" => 2),
    )
    sp = SirenProblem(components=[c1, c2], connectors=[conn1, conn2], tspan=(0.0, 10.0))
    solve(sp, alg)
end

@testitem "mtk" begin
    using ModelingToolkit, OrdinaryDiffEq
    using OrdinaryDiffEqLowOrderRK
    using ModelingToolkit: t_nounits as t, D_nounits as D

    @variables x(t) [irreducible=true] y(t) [irreducible=true]
    eqs = [D(x) ~ x - x * y
        D(y) ~ -y + x * y]
    @mtkcompile lv = System(eqs, t)
    prob = ODEProblem(lv, [x => 4.0, y => 2.0], (0.0, 0.1))

    solODE = solve(prob, Euler(); adaptive=false, dt=0.002)

    eqs = [D(x) ~ x - x * y
        D(y) ~ 0]
    @mtkcompile lv1 = System(eqs, t)
    prob = ODEProblem(lv1, [x => 4.0, y => 2.0], (0.0, 0.1))

    c1 = DEComponent(
        prob, Euler();
        name="Prey",
        timestep=0.002,
        state_names=OrderedDict("prey" => x, "predator" => y),
        intkwargs=(; adaptive=false, dt=0.002)
    )

    eqs = [D(x) ~ 0
        D(y) ~ -y + x * y]
    @mtkcompile lv2 = System(eqs, t)
    prob = ODEProblem(lv2, [x => 4.0, y => 2.0], (0.0, 0.1))

    c2 = DEComponent(
        prob, Euler();
        name="Predator",
        timestep=0.002,
        state_names=OrderedDict("prey" => x, "predator" => y),
        intkwargs=(; adaptive=false, dt=0.002)
    )

    conn1 = Connector(
        inputs=["Predator.predator"],
        outputs=["Prey.predator"]
    )
    conn2 = Connector(
        inputs=["Prey.prey"],
        outputs=["Predator.prey"]
    )

    sp = SirenProblem(components=[c1, c2], connectors=[conn1, conn2], tspan=(0.0, 0.1))

    using CommonSolve
    alg = MinimumTimeStepper()
    # Ensure the code is compiled
    sirenSol = solve(sp, alg)

    preyODE = [solODE(t; idxs=x) for t in sirenSol.t]
    predatorODE = [solODE(t; idxs=y) for t in sirenSol.t]

    @test all(sirenSol.t .≈ solODE.t)
    @test all(sirenSol["Prey.prey"] .≈ preyODE)
    @test all(sirenSol["Predator.predator"] .≈ predatorODE)
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
        name="Lotka-Volterra",
        timestep=0.002,
        state_names=OrderedDict("prey" => 1, "predator" => 2)
    )

    conn1 = Connector(
        inputs=["Lotka-Volterra.predator"],
        outputs=["other.predator"]
    )
    conn2 = Connector(
        inputs=["other.prey"],
        outputs=["Lotka-Volterra.prey"]
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

@testitem "DAE reinit" begin
    # A DAE system should be reinitialised with CheckInit (error if algebraic variables are not consistent) after setstate! is called.
    using OrdinaryDiffEq
    using OrdinaryDiffEqBDF

    # Simple DAE: x' = y, 0 = x + y - 1 (algebraic constraint)
    # Residual form: resid[1] = du[1] - y, resid[2] = x + y - 1
    function f!(resid, du, u, p, t)
        x, y = u
        resid[1] = du[1] - y
        resid[2] = x + y - 1  # algebraic constraint: 0 = x + y - 1
    end

    u0 = [0.5, 0.5]  # x + y = 1 (satisfies constraint)
    du0 = [0.5, 0.0]  # initial derivative for x, and 0 for algebraic variable y
    tspan = (0.0, 1.0)

    # Create DAE problem with index 1
    prob = DAEProblem(f!, du0, u0, tspan, differential_vars=[true, false])

    c1 = DEComponent(
        prob, DImplicitEuler();
        name="DAE_System",
        timestep=0.1,
        state_names=OrderedDict("x" => 1, "y" => 2)
    )

    integrator = init(c1)

    # Verify initial state satisfies constraint
    @test getstate(integrator, ConnectedVariable("DAE_System.x")) == 0.5
    @test getstate(integrator, ConnectedVariable("DAE_System.y")) == 0.5

    # Step the integrator
    step!(integrator)

    # Get current state
    x_val = getstate(integrator, ConnectedVariable("DAE_System.x"))
    y_val = getstate(integrator, ConnectedVariable("DAE_System.y"))

    # Verify that the algebraic constraint is satisfied
    @test x_val + y_val ≈ 1.0

    # Set state and verify it reinitializes properly
    # New state must also satisfy the algebraic constraint
    new_x = 0.3
    new_y = 0.7  # x + y = 1
    setstate!(integrator, ConnectedVariable("DAE_System.x"), new_x)
    setstate!(integrator, ConnectedVariable("DAE_System.y"), new_y)

    @test getstate(integrator, ConnectedVariable("DAE_System.x")) == new_x
    @test getstate(integrator, ConnectedVariable("DAE_System.y")) == new_y

    # Further stepping should work without initialization errors
    step!(integrator)

    # If the new state does not satisfy the algebraic constraint, it should throw an error
    new_x_invalid = 0.4
    new_y_invalid = 0.4  # x + y = 0.8 ≠ 1.0
    setstate!(integrator, ConnectedVariable("DAE_System.x"), new_x_invalid)
    setstate!(integrator, ConnectedVariable("DAE_System.y"), new_y_invalid)

    @test_skip SciMLBase.CheckInitFailureError #step!(integrator) # should be @test_throws
end
