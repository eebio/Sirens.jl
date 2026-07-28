@testitem "MOL" begin
    using OrdinaryDiffEq, ModelingToolkit, MethodOfLines, DomainSets
    using OrdinaryDiffEqLowOrderRK

    # Parameters, variables, and derivatives
    @parameters t x
    @variables u(..) g(..) [irreducible = true]
    Dt = Differential(t)
    Dx = Differential(x)
    Dxx = Differential(x)^2

    # 1D PDE and boundary conditions
    eq = [Dt(u(t, x)) ~ Dxx(u(t, x)) + g(t, x),
        Dt(g(t, x)) ~ 1]
    bcs = [u(0, x) ~ sin(pi * x),
        u(t, 0) ~ 0,
        u(t, 1) ~ 0,
        g(0, x) ~ 0.5,
        Dx(g(t, 0)) ~ 0,
        Dx(g(t, 1)) ~ 0]

    # Space and time domains
    domains = [t ∈ Interval(0.0, 0.01),
        x ∈ Interval(0.0, 1.0)]

    # PDE system
    @named pdesys = PDESystem(eq, bcs, domains, [t, x], [g(t, x), u(t, x)])

    dx = 0.1
    # Method of lines discretization
    discretization = MOLFiniteDifference([x => dx], t)

    # Convert the PDE problem into an ODE problem
    prob = discretize(pdesys, discretization)

    solPDE = solve(prob, Euler(), dt = 0.0001, adaptive = false)

    # Parameters, variables, and derivatives
    # 1D PDE and boundary conditions
    eq = [Dt(u(t, x)) ~ Dxx(u(t, x)) + g(t, x),
        Dt(g(t, x)) ~ 0]
    bcs = [u(0, x) ~ sin(pi * x),
        u(t, 0) ~ 0,
        u(t, 1) ~ 0,
        g(0, x) ~ 0,
        Dx(g(t, 0)) ~ 0,
        Dx(g(t, 1)) ~ 0]

    # Space and time domains
    domains = [t ∈ Interval(0.0, 0.01),
        x ∈ Interval(0.0, 1.0)]

    # PDE system
    @named pdesys = PDESystem(eq, bcs, domains, [t, x], [g(t, x), u(t, x)])

    dx = 0.1
    # Method of lines discretization
    discretization = MOLFiniteDifference([x => dx], t)

    # Convert the PDE problem into an ODE problem
    prob = discretize(pdesys, discretization)

    using SymbolicIndexingInterface
    function var_index(s)
        return variable_index(prob, ModelingToolkit.parse_variable(prob.f.sys, s))
    end

    c1 = MOLComponent(prob, Euler();
        name = "PDE",
        state_names = OrderedDict("u" => [var_index("u[" * string(i) * "]") for i in 2:10],
            "g" => [var_index("g[" * string(i) * "]") for i in 2:10]),
        timestep = 0.0001,
        intkwargs = (:adaptive => false, :dt => 0.0001)
    )

    function f2(u, p, t)
        return 1
    end
    u0 = 0.5
    tspan = (0.0, 0.01)
    prob = ODEProblem(f2, u0, tspan)
    c2 = DEComponent(
        prob, Euler();
        name = "G",
        timestep = 0.0001,
        state_names = OrderedDict("g" => 1),
        intkwargs = (:adaptive => false, :dt => 0.0001)
    )

    conn = Connector(
        inputs = ["G.g"],
        outputs = ["PDE.g[1:9]"]
    )

    mp = MermaidProblem(components = [c1, c2], connectors = [conn], tspan = (0.0, 0.01))
    sol = solve(mp, MinimumTimeStepper())
    finalsol = [0, sol(0.01)["PDE.u"]..., 0]
    @test all(isapprox.(finalsol, solPDE[u(t, x)][end, :], atol = 1e-8))
end

@testitem "state control" begin
    using OrdinaryDiffEq, ModelingToolkit, MethodOfLines, DomainSets, DiffEqBase
    @parameters t x
    @variables u(..) g(..) [irreducible = true]
    Dt = Differential(t)
    Dx = Differential(x)
    Dxx = Differential(x)^2

    # 1D PDE and boundary conditions
    eq = [Dt(u(t, x)) ~ Dxx(u(t, x)) + g(t, x),
        Dt(g(t, x)) ~ 1]
    bcs = [u(0, x) ~ sin(pi * x),
        u(t, 0) ~ 0,
        u(t, 1) ~ 0,
        g(0, x) ~ 0.5,
        Dx(g(t, 0)) ~ 0,
        Dx(g(t, 1)) ~ 0]

    # Space and time domains
    domains = [t ∈ Interval(0.0, 0.01),
        x ∈ Interval(0.0, 1.0)]

    # PDE system
    @named pdesys = PDESystem(eq, bcs, domains, [t, x], [g(t, x), u(t, x)])

    dx = 0.1
    # Method of lines discretization
    discretization = MOLFiniteDifference([x => dx], t)

    # Convert the PDE problem into an ODE problem
    prob = discretize(pdesys, discretization)

    using SymbolicIndexingInterface
    function var_index(s)
        return variable_index(prob, ModelingToolkit.parse_variable(prob.f.sys, s))
    end

    c1 = MOLComponent(prob, Tsit5();
        name = "PDE",
        state_names = OrderedDict("u" => [var_index("u[" * string(i) * "]") for i in 2:10],
            "g" => [var_index("g[" * string(i) * "]") for i in 2:10]),
        timestep = 0.0001
    )

    conn1 = Connector(
        inputs = ["PDE.u[1:9]"],
        outputs = ["other.u"]
    )
    conn2 = Connector(
        inputs = ["PDE.g[1:9]"],
        outputs = ["other.g"]
    )
    integrator = init(c1)

    @test issetequal(variables(integrator), ["u", "g", "#time", "#integrator", "#state"])

    # Check initial state
    @test getstate(integrator, ConnectedVariable("PDE.u")) ==
          [sin(pi * x) for x in 0.1:0.1:0.9]
    @test getstate(integrator, ConnectedVariable("PDE.g")) == [0.5 for _ in 0.1:0.1:0.9]
    @test getstate(integrator) ==
          [[sin(pi * x) for x in [0.1:0.1:0.9...]]...; [0.5 for _ in [0.1:0.1:0.9...]]][[
        c1.state_names["u"]..., c1.state_names["g"]...]]
    @test getstate(integrator, ConnectedVariable("PDE.u[1]")) == sin(pi * 0.1)
    @test getstate(integrator, ConnectedVariable("PDE.g[1:3]")) == [0.5, 0.5, 0.5]
    @test getstate(integrator, ConnectedVariable("PDE.u[2:4]")) ==
          [sin(pi * 0.2), sin(pi * 0.3), sin(pi * 0.4)]
    # Check setting state
    setstate!(integrator, ConnectedVariable("PDE.u"), [1.0 for _ in 0.1:0.1:0.9])
    @test getstate(integrator, ConnectedVariable("PDE.u")) == [1.0 for _ in 0.1:0.1:0.9]
    @test getstate(integrator, ConnectedVariable("PDE.g")) == [0.5 for _ in 0.1:0.1:0.9]
    setstate!(integrator, ConnectedVariable("PDE.u[1]"), 0.0)
    @test getstate(integrator, ConnectedVariable("PDE.u")) ==
          [0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    setstate!(integrator, ConnectedVariable("PDE.g[1:3]"), [0.0, 0.1, 0.2])
    @test getstate(integrator, ConnectedVariable("PDE.g")) ==
          [0.0, 0.1, 0.2, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]

    # Check time control
    @test gettime(integrator) == 0.0
    step!(integrator)
    @test gettime(integrator) == 0.0001
    settime!(integrator, 0.001)
    @test gettime(integrator) == 0.001
    step!(integrator)
    @test gettime(integrator) == 0.0011

    # Step means the state has changed
    @test getstate(integrator, ConnectedVariable("PDE.u")) ≠
          [0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    @test getstate(integrator, ConnectedVariable("PDE.g")) ≠
          [0.0, 0.1, 0.2, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]

    # Global setstate!
    setstate!(integrator, [-1.0 for _ in 1:18])
    @test getstate(integrator, ConnectedVariable("PDE.u")) == [-1.0 for _ in 0.1:0.1:0.9]
    @test getstate(integrator, ConnectedVariable("PDE.g")) == [-1.0 for _ in 0.1:0.1:0.9]

    # Test error on symbolic indexing
    c1 = MOLComponent(prob, Tsit5();
        name = "PDE",
        state_names = OrderedDict("u" => u, "g" => g),
        timestep = 0.0001
    )
    int = init(c1)
    @test_throws ArgumentError getstate(int, ConnectedVariable("PDE.u"))

    # Reset to numeric state_names for special variable tests
    c1 = MOLComponent(prob, Tsit5();
        name = "PDE",
        state_names = OrderedDict("u" => [var_index("u[" * string(i) * "]") for i in 2:10],
            "g" => [var_index("g[" * string(i) * "]") for i in 2:10]),
        timestep = 0.0001
    )
    int = init(c1)

    # Test special variable #state
    @test "#state" in variables(int)
    state_via_special = getstate(int, ConnectedVariable("PDE.#state"))
    @test state_via_special isa Vector
    @test length(state_via_special) == 18
    original_state = copy(state_via_special)
    new_state = [-2.0 for _ in 1:18]
    setstate!(int, ConnectedVariable("PDE.#state"), deepcopy(new_state))
    @test getstate(int, ConnectedVariable("PDE.#state")) == new_state
    @test getstate(int) == new_state

    # Test special variable #integrator
    @test "#integrator" in variables(int)
    integrator_copy = getstate(int, ConnectedVariable("PDE.#integrator"); copy = true)
    @test typeof(integrator_copy) <: SciMLBase.DEIntegrator
    @test integrator_copy.u == new_state
    # Modify state and step
    step!(int)
    @test getstate(int) ≠ new_state
    # Restore integrator state
    setstate!(int, ConnectedVariable("PDE.#integrator"), integrator_copy)
    @test getstate(int) == new_state
end
