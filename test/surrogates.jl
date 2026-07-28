@testitem "surrogate integrator 1d" begin
    using OrdinaryDiffEq
    using Flux
    using Surrogates
    using Random
    using Mermaid
    Random.seed!(0)
    # Define a simple ODE: dx/dt = -x, x(0) = 1
    f(u, p, t) = -u
    u0 = 1.0
    tspan = (0.0, 1.0)
    prob = ODEProblem(f, u0, tspan)
    state_names = OrderedDict("x" => 1)
    ode_comp = Mermaid.DEComponent(
        prob, Rodas5P(); name = "decay", state_names = state_names, timestep = 0.1)

    # Set bounds for surrogate sampling
    lower = [0.0]
    upper = [1.0]

    model = f64(Chain(
        Dense(1, 16, relu),
        Dense(16, 1)
    ))
    # Create surrogate component
    surrogate_comp = SurrogateComponent(
        ode_comp,
        NeuralSurrogate,
        lower,
        upper;
        kwargs = (model = model, n_epochs = 4000)
    )

    # Initialize both components
    ode_int = init(ode_comp)
    surrogate_int = init(surrogate_comp)

    # Step both integrators and compare
    n_steps = 20
    tol = 0.01  # Surrogate tolerance

    for i in 1:n_steps
        step!(ode_int)
        step!(surrogate_int)
        orig = getstate(ode_int, ConnectedVariable("decay.x"))
        sur = getstate(surrogate_int, ConnectedVariable("decay.x"))
        @test isapprox(sur, orig; atol = tol)
    end
end

@testitem "surrogate integrator 2d" begin
    using OrdinaryDiffEq
    using Surrogates, Flux
    using Random
    Random.seed!(0)
    # Define a simple ODE: dx/dt = -x, x(0) = 1
    f(u, p, t) = [-u[1], u[2] - u[1]]
    u0 = [1.0, 0.5]
    tspan = (0.0, 1.0)
    prob = ODEProblem(f, u0, tspan)
    state_names = OrderedDict("x" => 1)
    ode_comp = DEComponent(
        prob, Rodas5P(); name = "decay", state_names = state_names, timestep = 0.1)

    # Set bounds for surrogate sampling
    lower = [0.0, 0.0]
    upper = [1.0, 1.0]

    # Create surrogate component
    surrogate_comp = SurrogateComponent(
        ode_comp,
        NeuralSurrogate,
        lower,
        upper;
        n_samples = 2000,
        kwargs = (n_epochs = 4000, model = Chain(Dense(2, 16, relu), Dense(16, 2)))
    )

    # Initialize both components
    ode_int = init(ode_comp)
    surrogate_int = init(surrogate_comp)

    # Step both integrators and compare
    n_steps = 20
    tol = 0.1  # Looser tolerances to save training time in tests
    @test surrogate_int.surrogate isa NeuralSurrogate
    for i in 1:n_steps
        step!(ode_int)
        step!(surrogate_int)
        orig = getstate(ode_int, ConnectedVariable("decay.x"))
        sur = getstate(surrogate_int, ConnectedVariable("decay.x"))
        @test isapprox(sur, orig; atol = tol)
    end
end

@testitem "surrogate integrator non-neural" begin
    using OrdinaryDiffEq
    using Surrogates
    using Random
    Random.seed!(0)
    # Define a simple ODE: dx/dt = -x, x(0) = 1
    f(u, p, t) = [-u[1], u[2] - u[1]]
    u0 = [1.0, 0.5]
    tspan = (0.0, 1.0)
    prob = ODEProblem(f, u0, tspan)
    state_names = OrderedDict("x" => 1)
    ode_comp = DEComponent(
        prob, Rodas5P(); name = "decay", state_names = state_names, timestep = 0.1)

    # Set bounds for surrogate sampling
    lower = [0.0, 0.0]
    upper = [1.0, 1.0]

    # Create surrogate component
    surrogate_comp = SurrogateComponent(
        ode_comp,
        SecondOrderPolynomialSurrogate,
        lower,
        upper;
        n_samples = 2000
    )

    # Dummy connector list (no connections for this test)
    conns = Connector[]

    # Initialize both components
    ode_int = init(ode_comp)
    surrogate_int = init(surrogate_comp)

    # Step both integrators and compare
    n_steps = 20
    tol = 0.1  # Looser tolerances to save training time in tests
    @test surrogate_int.surrogate isa SecondOrderPolynomialSurrogate
    for i in 1:n_steps
        step!(ode_int)
        step!(surrogate_int)
        orig = getstate(ode_int, ConnectedVariable("decay.x"))
        sur = getstate(surrogate_int, ConnectedVariable("decay.x"))
        @test isapprox(sur, orig; atol = tol)
    end
end

@testitem "state control" begin
    using OrdinaryDiffEq
    using Surrogates, Flux
    # Define a simple ODE: dx/dt = -x, x(0) = 1
    f(u, p, t) = [-u[1], u[2] - u[1]]
    u0 = [1.0, 0.5]
    tspan = (0.0, 1.0)
    prob = ODEProblem(f, u0, tspan)
    state_names = OrderedDict("x" => 1, "y" => 2)
    ode_comp = DEComponent(
        prob, Rodas5P(); name = "decay", state_names = state_names, timestep = 0.1)

    # Set bounds for surrogate sampling
    lower = [0.0, 0.0]
    upper = [1.0, 1.0]

    # Create surrogate component
    surrogate_comp = SurrogateComponent(
        ode_comp,
        NeuralSurrogate,
        lower,
        upper;
        n_samples = 10,
        kwargs = (n_epochs = 100, model = Chain(Dense(2, 8, relu), Dense(8, 2)))
    )

    # Initialize both components
    surrogate_int = init(surrogate_comp)

    @test getstate(surrogate_int, ConnectedVariable("decay.x")) == 1.0
    @test getstate(surrogate_int, ConnectedVariable("decay.y")) == 0.5
    @test getstate(surrogate_int) == [1.0, 0.5]
    setstate!(surrogate_int, ConnectedVariable("decay.x"), 0.75)
    @test getstate(surrogate_int, ConnectedVariable("decay.x")) == 0.75
    @test getstate(surrogate_int, ConnectedVariable("decay.y")) == 0.5
    @test getstate(surrogate_int) == [0.75, 0.5]

    @test gettime(surrogate_int) == 0.0

    step!(surrogate_int)
    @test getstate(surrogate_int, ConnectedVariable("decay.x")) ≠ 0.75
    @test all(getstate(surrogate_int) .≠ [0.75, 0.5])

    setstate!(surrogate_int, [0.9, 0.1])
    @test getstate(surrogate_int, ConnectedVariable("decay.x")) == 0.9
    @test getstate(surrogate_int, ConnectedVariable("decay.y")) == 0.1
    @test getstate(surrogate_int) == [0.9, 0.1]

    @test gettime(surrogate_int) == 0.1
    settime!(surrogate_int, 0.5)
    @test gettime(surrogate_int) == 0.5
    step!(surrogate_int)
    @test gettime(surrogate_int) == 0.6
    @test issetequal(variables(surrogate_int), ["x", "y", "#time", "#integrator", "#state"])
end
