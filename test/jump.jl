@testitem "jump" begin
    using OrdinaryDiffEq, JumpProcesses

    β = 0.1 / 1000.0
    ν = 0.01
    p = (β, ν)
    rate1(u, p, t) = p[1] * u[1] * u[2]  # β*S*I
    function affect1!(integrator)
        integrator.u[1] -= 1         # S -> S - 1
        integrator.u[2] += 1         # I -> I + 1
        nothing
    end
    jump = ConstantRateJump(rate1, affect1!)

    rate2(u, p, t) = p[2] * u[2]         # ν*I
    function affect2!(integrator)
        integrator.u[2] -= 1        # I -> I - 1
        integrator.u[3] += 1        # R -> R + 1
        nothing
    end
    jump2 = ConstantRateJump(rate2, affect2!)

    u₀ = [990, 0, 0]
    tspan = (0.0, 250.0)

    prob = DiscreteProblem(u₀, tspan, p)

    jump_prob = JumpProblem(prob, Direct(), jump, jump2)

    c = JumpComponent(jump_prob, SSAStepper();
        name = "SIR",
        state_names = Dict("S" => 1, "I" => 2, "R" => 3),
        timestep = 1.0
    )

    mp = MermaidProblem(components = [c], connectors = []; tspan = tspan)
    sol = solve(mp, MinimumTimeStepper())

    @test all(sol["SIR.S"] .== 990) # No infected to model won't change
    @test all(sol["SIR.R"] .== 0) # No infected to model won't change
    @test all(sol["SIR.I"] .== 0) # No infected to model won't change

    function f(u, p, t)
        return 1.0
    end
    u₀ = 0.0
    odeprob = ODEProblem(f, u₀, tspan, nothing)
    odecomp = DEComponent(odeprob, Tsit5();
        name = "ODE",
        state_names = Dict("u" => 1),
        timestep = 1.0
    )

    conn = Connector(
        inputs = ["ODE.u"],
        outputs = ["SIR.I"],
        func = x -> round(Int, x)
    )
    mp2 = MermaidProblem(components = [odecomp, c], connectors = [conn]; tspan = tspan)
    sol2 = solve(mp2, MinimumTimeStepper())

    @test !all(sol2["SIR.S"] .== 990)
    @test !all(sol2["SIR.R"] .== 0)
    @test !all(sol2["SIR.I"] .== 0)
    @test sol2["SIR.I"][1] == 0
end

@testitem "hybrid jump ode" begin
    using OrdinaryDiffEq, JumpProcesses
    using OrdinaryDiffEqLowOrderRK

    β = 0.1 / 1000.0
    ν = 0.01
    p = (β, ν)

    function f1(du, u, p, t)
        du[4] = 0 # This will be controlled by Mermaid
        nothing
    end
    tspan = (0.0, 250.0)
    u₀ = [990.0, 10.0, 0.0, 100.0]
    prob = ODEProblem(f1, u₀, tspan, p)

    rate1(u, p, t) = p[1] * u[1] * u[2]  # β*S*I
    function affect1!(integrator)
        integrator.u[1] -= 1         # S -> S - 1
        integrator.u[2] += 1         # I -> I + 1
        nothing
    end
    jump = ConstantRateJump(rate1, affect1!)

    rate2(u, p, t) = p[2] * u[2]         # ν*I
    function affect2!(integrator)
        integrator.u[2] -= 1        # I -> I - 1
        integrator.u[3] += 1        # R -> R + 1
        nothing
    end
    jump2 = ConstantRateJump(rate2, affect2!)

    jump_prob = JumpProblem(prob, Direct(), jump, jump2)

    c = JumpComponent(jump_prob, Tsit5();
        name = "SIR",
        state_names = Dict("S" => 1, "I" => 2, "R" => 3, "u" => 4),
        timestep = 1.0,
        intkwargs = (:adaptive => false, :dt => 0.002)
    )

    # Override the dynamics of the ODE with our own ODE
    function f2(u, p, t)
        return 1.0
    end
    u₀ = 0.0
    odeprob = ODEProblem(f2, u₀, tspan, nothing)
    odecomp = DEComponent(odeprob, Euler();
        name = "ODE",
        state_names = Dict("u" => 1),
        timestep = 1.0,
        intkwargs = (:adaptive => false, :dt => 0.002)
    )

    conn = Connector(
        inputs = ["ODE.u"],
        outputs = ["SIR.u"],
        func = x -> round(Int, x)
    )

    mp = MermaidProblem(components = [c, odecomp], connectors = [conn]; tspan = tspan)
    sol = solve(mp, MinimumTimeStepper())
    @test 240.0 < sol["SIR.u"][end] < 250.0
end

@testitem "state control" begin
    using Random
    Random.seed!(1234)
    using OrdinaryDiffEq, JumpProcesses

    β = 0.1 / 1000.0
    ν = 0.01
    p = (β, ν)
    rate1(u, p, t) = p[1] * u[1] * u[2]  # β*S*I
    function affect1!(integrator)
        integrator.u[1] -= 1         # S -> S - 1
        integrator.u[2] += 1         # I -> I + 1
        nothing
    end
    jump = ConstantRateJump(rate1, affect1!)

    rate2(u, p, t) = p[2] * u[2]         # ν*I
    function affect2!(integrator)
        integrator.u[2] -= 1        # I -> I - 1
        integrator.u[3] += 1        # R -> R + 1
        nothing
    end
    jump2 = ConstantRateJump(rate2, affect2!)

    u₀ = [990, 10, 0]
    tspan = (0.0, 250.0)

    prob = DiscreteProblem(u₀, tspan, p)

    jump_prob = JumpProblem(prob, Direct(), jump, jump2)

    c = JumpComponent(jump_prob, SSAStepper();
        name = "SIR",
        state_names = Dict("S" => 1, "I" => 2, "R" => 3),
        timestep = 50.0
    )

    int = init(c)
    @test getstate(int, ConnectedVariable("SIR.S")) == 990
    @test getstate(int, ConnectedVariable("SIR.I")) == 10
    @test getstate(int, ConnectedVariable("SIR.R")) == 0
    @test getstate(int) == [990, 10, 0]

    setstate!(int, ConnectedVariable("SIR.S"), 900)
    @test getstate(int, ConnectedVariable("SIR.S")) == 900
    @test getstate(int, ConnectedVariable("SIR.I")) == 10
    @test getstate(int, ConnectedVariable("SIR.R")) == 0
    @test getstate(int) == [900, 10, 0]

    setstate!(int, [800, 20, 0])
    @test getstate(int, ConnectedVariable("SIR.S")) == 800
    @test getstate(int, ConnectedVariable("SIR.I")) == 20
    @test getstate(int, ConnectedVariable("SIR.R")) == 0
    @test getstate(int) == [800, 20, 0]

    setstate!(int, ConnectedVariable("SIR.I"), 0)
    @test getstate(int, ConnectedVariable("SIR.S")) == 800
    @test getstate(int, ConnectedVariable("SIR.I")) == 0
    @test getstate(int, ConnectedVariable("SIR.R")) == 0
    @test getstate(int) == [800, 0, 0]

    step!(int)
    @test getstate(int, ConnectedVariable("SIR.S")) == 800
    @test getstate(int, ConnectedVariable("SIR.I")) == 0
    @test getstate(int, ConnectedVariable("SIR.R")) == 0
    @test getstate(int) == [800, 0, 0]

    step!(int)
    @test getstate(int, ConnectedVariable("SIR.S")) == 800
    @test getstate(int, ConnectedVariable("SIR.I")) == 0
    @test getstate(int, ConnectedVariable("SIR.R")) == 0
    @test getstate(int) == [800, 0, 0]

    setstate!(int, ConnectedVariable("SIR.I"), 100)
    step!(int)
    # Rates are high so we should see a change from step! - techically a random test though
    @test getstate(int, ConnectedVariable("SIR.S")) != 800
    @test getstate(int, ConnectedVariable("SIR.I")) != 100
    @test getstate(int, ConnectedVariable("SIR.R")) != 0

    @test gettime(int) == 150.0
    settime!(int, 200.0)
    @test gettime(int) == 200.0
    step!(int)
    @test gettime(int) == 250.0

    setstate!(int, [700, 20, 10])
    @test getstate(int) == [700, 20, 10]

    # Test special variable #state
    @test "#state" in variables(int)
    state_via_special = getstate(int, ConnectedVariable("SIR.#state"))
    @test state_via_special == [700, 20, 10]
    @test state_via_special isa Vector
    setstate!(int, ConnectedVariable("SIR.#state"), [500, 50, 100])
    @test getstate(int) == [500, 50, 100]
    @test getstate(int, ConnectedVariable("SIR.#state")) == [500, 50, 100]

    # Test special variable #integrator
    @test "#integrator" in variables(int)
    integrator_copy = getstate(int, ConnectedVariable("SIR.#integrator"); copy = true)
    @test typeof(integrator_copy) <: JumpProcesses.SSAIntegrator
    @test integrator_copy.u == [500, 50, 100]
    # Modify and step
    step!(int)
    old_state = getstate(int)
    # Restore integrator state
    setstate!(int, ConnectedVariable("SIR.#integrator"), integrator_copy)
    @test getstate(int) == [500, 50, 100]
end
