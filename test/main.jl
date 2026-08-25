@testitem "fullname" begin
    @test fullname(ConnectedVariable("comp", "var", [1:5...], [1, 3, 5, 7])) ==
          "comp[[1, 3, 5, 7]].var[[1, 2, 3, 4, 5]]"
    @test fullname(ConnectedVariable("cmp", "var", [1:5...], nothing)) == "cmp.var[[1, 2, 3, 4, 5]]"
    @test fullname(ConnectedVariable("cp", "vr", nothing, [1, 3, 5, 7])) ==
          "cp[[1, 3, 5, 7]].vr"
    @test fullname(ConnectedVariable("comp", "var", nothing, nothing)) == "comp.var"
end

@testitem "solution" begin
    using Agents, OrdinaryDiffEq

    space = GridSpace((20, 20))

    @agent struct Schelling(GridAgent{2})
        mood::Bool = false
        group::Int
    end

    function schelling_step!(agent, model)
        minhappy = model.min_to_be_happy
        count_neighbors_same_group = 0
        for neighbor in nearby_agents(agent, model)
            if agent.group == neighbor.group
                count_neighbors_same_group += 1
            end
        end
        if count_neighbors_same_group ≥ minhappy
            agent.mood = true
        else
            agent.mood = false
            move_agent_single!(agent, model)
        end
        return
    end

    properties = Dict(:min_to_be_happy => 3.0, :list_property => [1, 2, 3, 4, 5])

    model = StandardABM(
        Schelling,
        space;
        (agent_step!)=schelling_step!, properties
    )

    for n in 1:20
        add_agent_single!(model; group=n < 20 / 2 ? 1 : 2)
    end

    c1 = AgentsComponent(model;
        name="Schelling",
        state_names=OrderedDict("min_to_be_happy" => :min_to_be_happy,
            "list_property" => :list_property, "mood" => :mood, "group" => :group),
        timestep=1.0
    )

    sp = SirenProblem(components=[c1], connectors=[], tspan=(0.0, 10.0))

    alg = MinimumTimeStepper()
    sol = solve(sp, alg)
    @test sol["Schelling.min_to_be_happy"] == [3.0 for _ in sol.t]
    @test sol["Schelling.list_property"] == [[1, 2, 3, 4, 5] for _ in sol.t]
    @test sol["Schelling.list_property[2:3]"] == [[2, 3] for _ in sol.t]
    @test sol["Schelling.mood"] == sol[ConnectedVariable("Schelling.mood")]

    # Test indexing
    @test sol[2].t[1] == sol.t[2]
    @test length(sol[2].t) == 1
    @test (sol[2].u)[ConnectedVariable("Schelling.min_to_be_happy")] ==
          sol["Schelling.min_to_be_happy"][2]
    @test sol[2] isa SirenSolution
    @test keys(sol[2].u) == keys(sol.u)

    # Test interpolation
    @test sol(2) isa SirenSolution
    @test sol(2).t[1] == 2.0
    sol.u[ConnectedVariable("Schelling.min_to_be_happy")][4] = rand()
    @test sol(2.75).t[1] == 2.75
    @test length(sol(2.75).t) == 1
    @test sol(2.75)["Schelling.min_to_be_happy"] ≈
          (sol.u[ConnectedVariable("Schelling.min_to_be_happy")][3] +
           3 * sol.u[ConnectedVariable("Schelling.min_to_be_happy")][4]) / 4
    @test sol(2)["Schelling.min_to_be_happy"] == 3.0
    @test sol(3)["Schelling.min_to_be_happy"] ≠ 3.0

    # Test error handling
    @test_throws BoundsError sol[1000]
    @test_throws BoundsError sol(1000)

    # save_vars
    sp = SirenProblem(components=[c1], connectors=[], tspan=(0.0, 10.0))
    sol = solve(
        sp, alg; save_vars=["Schelling.min_to_be_happy", "Schelling.list_property[2:4]"])
    @test sol["Schelling.min_to_be_happy"] == [3.0 for _ in sol.t]
    @test_throws KeyError sol["Schelling.mood"]
    @test issetequal(keys(sol.u),
        ConnectedVariable.(["Schelling.min_to_be_happy", "Schelling.list_property[2:4]"]))
    @test sol["Schelling.list_property[2:3]"] == [[2, 3] for _ in sol.t]
    @test sol["Schelling.list_property[2]"] == [2 for _ in sol.t]
    @test sol["Schelling.list_property[3]"] == [3 for _ in sol.t]
    @test sol["Schelling.list_property[2:4]"] == [[2, 3, 4] for _ in sol.t]
    @test_throws KeyError sol["Schelling.list_property[1:5]"]
    @test_throws KeyError sol["Schelling.list_property"]

    # saveat
    sp = SirenProblem(components=[c1], connectors=[], tspan=(0.0, 10.0))
    sol = solve(sp, alg; saveat=2)
    @test sol.t == [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]
    # Checks it happens even if the saveat doesn't line up with the time steps
    sol = solve(sp, alg; saveat=2.5)
    @test sol.t == [0.0, 2.5, 5.0, 7.5, 10.0]
    # Check function form
    sol = solve(sp, alg; saveat=(integrator, t) -> t == 5.0 || t == 8.0)
    @test sol.t == [5.0, 8.0]
    # Default is all time steps
    sol = solve(sp, alg)
    @test sol.t == 0.0:1.0:10.0

    # save_vars
    sol = solve(sp, alg; save_vars=:all)
    @test issetequal(keys(sol.u),
        ConnectedVariable.([
            "Schelling.min_to_be_happy", "Schelling.list_property", "Schelling.mood",
            "Schelling.group", "Schelling.#model", "Schelling.#time", "Schelling.#model", "Schelling.#ids"
        ]))
    sol = solve(sp, alg)
    @test issetequal(keys(sol.u),
        ConnectedVariable.([
            "Schelling.min_to_be_happy", "Schelling.list_property", "Schelling.mood",
            "Schelling.group",
        ]))
    sol = solve(sp, alg; save_vars=:none)
    @test issetequal(keys(sol.u), [])
    sol = solve(sp, alg; save_vars=["Schelling.list_property", "Schelling.#model"])
    @test issetequal(keys(sol.u),
        ConnectedVariable.([
            "Schelling.list_property", "Schelling.#model",
        ]))

    # Test interpolation with non-numeric types (constant interpolation)
    sol = solve(sp, alg; save_vars=:all, saveat=2)
    @test length(sol.t) == 6  # [0, 2, 4, 6, 8, 10]
    # For non-numeric types like #model, interpolation should use constant interpolation
    # (returning the state from the last saved time point)
    interpolated_sol = sol(3.0)  # Between sol.t[1]=2 and sol.t[2]=4
    model_at_2 = sol["Schelling.#model"][2]
    model_at_3 = interpolated_sol["Schelling.#model"]
    # Constant interpolation: model at time 3 should be the same object as model at time 2
    @test model_at_3 === model_at_2
    # Verify numeric types still use linear interpolation
    list_prop_at_2 = sol["Schelling.list_property"][2]
    list_prop_at_3 = interpolated_sol["Schelling.list_property"]
    list_prop_at_4 = sol["Schelling.list_property"][3]
    # For numeric types, should interpolate: at t=3 (halfway), should be (value@2 + value@4) / 2
    @test list_prop_at_3 ≈ (list_prop_at_2 .+ list_prop_at_4) ./ 2

    # Test single saved point
    sol = solve(sp, alg; saveat=[5.0])
    @test length(sol.t) == 1
    @test sol.t[1] == 5.0
    @test sol(5.0)["Schelling.min_to_be_happy"] == sol["Schelling.min_to_be_happy"][1]
    @test_throws BoundsError sol(4.0)
    @test_throws BoundsError sol(6.0)

    # Default behaviour of get of dict
    @test get(sol.u, ConnectedVariable("Schell.min_to_be_happy"), :default) == :default
end

@testitem "siren integrator" begin
    using OrdinaryDiffEq
    using OrdinaryDiffEqLowOrderRK

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
    u0 = [4.0, 2.0]
    tspan = (0.0, 1.0)
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

    sp = SirenProblem(
        components=[c1, c2], connectors=[conn1, conn2], tspan=(0.0, 1.0))
    integrator = init(sp, MinimumTimeStepper())

    # State control
    @test getstate(integrator, ConnectedVariable("Prey.prey")) == 4.0
    @test getstate(integrator, ConnectedVariable("Predator.predator")) == 2.0
    setstate!(integrator, ConnectedVariable("Prey.prey"), 5.0)
    @test getstate(integrator, ConnectedVariable("Prey.prey")) == 5.0
    @test getstate(integrator, ConnectedVariable("Predator.predator")) == 2.0
    @test getstate(integrator.integrators[1], ConnectedVariable("Prey.prey")) == 5.0
    step!(integrator)
    @test getstate(integrator, ConnectedVariable("Prey.prey")) ≠ 5.0
    @test getstate(integrator, ConnectedVariable("Predator.predator")) ≠ 2.0

    # update_inputs!
    integrator = init(sp, MinimumTimeStepper())
    for conn in integrator.connectors
        runconnection!(integrator, conn)
    end
    @test getstate(integrator, ConnectedVariable("Prey.predator")) == 2.0
    @test getstate(integrator, ConnectedVariable("Predator.prey")) == 4.0

    conn1 = Connector(
        inputs=["Predator.predator"],
        outputs=["Prey.predator"],
        func=x -> x * 4
    )
    conn2 = Connector(
        inputs=["Prey.prey"],
        outputs=["Predator.prey"],
        func=x -> x / 1.5
    )
    sp = SirenProblem(
        components=[c1, c2], connectors=[conn1, conn2], tspan=(0.0, 1.0))
    integrator = init(sp, MinimumTimeStepper())
    for conn in integrator.connectors
        runconnection!(integrator, conn)
    end
    @test getstate(integrator, ConnectedVariable("Prey.predator")) == 8.0
    @test getstate(integrator, ConnectedVariable("Predator.prey")) == 4.0 / 1.5

    conn1 = Connector(
        inputs=["Predator.predator", "Predator.prey"],
        outputs=["Prey.predator", "Prey.prey"],
        func=(x, y) -> x * y
    )
    sp = SirenProblem(components=[c1, c2], connectors=[conn1], tspan=(0.0, 1.0))
    integrator = init(sp, MinimumTimeStepper())
    setstate!(integrator, ConnectedVariable("Predator.predator"), 2.0)
    setstate!(integrator, ConnectedVariable("Predator.prey"), 4.0)
    for conn in integrator.connectors
        runconnection!(integrator, conn)
    end
    @test getstate(integrator, ConnectedVariable("Prey.predator")) == 8.0
    @test getstate(integrator, ConnectedVariable("Prey.prey")) == 8.0

    # Incorrect connectors
    conn1 = Connector(
        inputs=["Predator.predator"],
        outputs=["Prey.predator_but_spelled_wrong"]
    )
    sp = SirenProblem(components=[c1, c2], connectors=[conn1], tspan=(0.0, 1.0))
    @test_throws KeyError solve(sp, MinimumTimeStepper())

    using Agents
    space = GridSpace((20, 20))

    @agent struct Schelling(GridAgent{2})
        mood::Vector{Float64} = Float64[]
        group::Int
    end
    function schelling_step!(agent, model)
        return nothing
    end
    properties = Dict(:min_to_be_happy => 3.0, :list_property => [1, 2, 3, 4, 5])
    model = StandardABM(
        Schelling,
        space;
        (agent_step!)=schelling_step!, properties
    )
    for n in 1:300
        add_agent_single!(model; group=n < 20 / 2 ? 1 : 2)
    end
    c1 = AgentsComponent(model;
        name="Schelling",
        state_names=OrderedDict("min_to_be_happy" => :min_to_be_happy,
            "list_property" => :list_property, "mood" => :mood, "group" => :group),
        timestep=1.0
    )
    conn1 = Connector(
        inputs=["Schelling.group[1]", "Schelling.group[2]", "Schelling.group[3]"],
        outputs=["Schelling.list_property"]
    )
    sp = SirenProblem(components=[c1], connectors=[conn1], tspan=(0.0, 10.0))
    alg = MinimumTimeStepper()

    int = init(sp, alg)
    @test getstate(int, ConnectedVariable("Schelling.list_property")) == [1, 2, 3, 4, 5]
    step!(int)
    @test getstate(int, ConnectedVariable("Schelling.list_property")) == [1, 1, 1]

    # Test copying
    a = getstate(int, ConnectedVariable("Schelling.list_property"); copy=false)
    a[2] = 2
    @test getstate(int, ConnectedVariable("Schelling.list_property")) == [1, 2, 1]
    a = getstate(int, ConnectedVariable("Schelling.list_property"); copy=true)
    a[2] = 3
    @test getstate(int, ConnectedVariable("Schelling.list_property")) == [1, 2, 1]
    a = getstate(int, ConnectedVariable("Schelling.list_property"))
    a[2] = 4
    @test getstate(int, ConnectedVariable("Schelling.list_property")) == [1, 4, 1]

    @test gettime(int) == 1.0
    step!(int)
    @test gettime(int) == 2.0

    # If component name is wrong
    @test isnothing(getstate(int, ConnectedVariable("Schell.list_property")))
    setstate!(int, ConnectedVariable("Schell.list_property"), [1, 2, 3])

    @test Sirens._has_component(sp.components, "Schell") == false
    @test Sirens._has_component(sp.components, "Schelling") == true
end

@testitem "non-advancing component throws error" begin
    using Sirens, CommonSolve

    struct StuckComponent <: AbstractComponent
        name::String
        timestep::Float64
    end

    mutable struct StuckIntegrator <: AbstractComponentIntegrator
        component::StuckComponent
        t::Float64
    end

    function CommonSolve.init(c::StuckComponent)
        return StuckIntegrator(c, 0.0)
    end

    function CommonSolve.step!(compInt::StuckIntegrator)
        # Intentionally does not advance time
    end

    function Sirens.getstate(compInt::StuckIntegrator, key)
        return compInt.t
    end

    function Sirens.getstate(compInt::StuckIntegrator)
        return compInt.t
    end

    function Sirens.setstate!(compInt::StuckIntegrator, key, value)
        if key.variable == "#time"
            compInt.t = value
        end
    end

    function Sirens.setstate!(compInt::StuckIntegrator, value)
        compInt.t = value
    end

    function Sirens.variables(component::StuckComponent)
        return ["#time"]
    end

    comp = StuckComponent("Stuck", 0.1)
    sp = SirenProblem(components=[comp], connectors=[], tspan=(0.0, 1.0))
    @test_throws "Component Stuck failed to advance: time did not move forward from 0.0." solve(sp, MinimumTimeStepper())
end

@testitem "timescales" begin
    using OrdinaryDiffEq
    using OrdinaryDiffEqLowOrderRK

    function f1!(du, u, p, t)
        x, y = u
        du[1] = x - x * y
        du[2] = 0
    end
    function f2!(du, u, p, t)
        y, x = u
        du[1] = (-y + x * y) / 60
        du[2] = 0
    end
    function f3!(du, u, p, t)
        y, x = u
        du[1] = -y + x * y
        du[2] = 0
    end

    prob1 = ODEProblem(f1!, [4.0, 2.0], (0.0, Inf))
    prob2 = ODEProblem(f2!, [2.0, 4.0], (0.0, Inf))
    prob3 = ODEProblem(f3!, [2.0, 4.0], (0.0, Inf))

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
        timestep=0.002 * 60,
        state_names=OrderedDict("predator" => 1, "prey" => 2),
        intkwargs=(; adaptive=false, dt=0.002*60)
    )

    c3 = DEComponent(
        prob3, Euler();
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

    mp1 = SirenProblem(
        components=[c1, c2], connectors=[conn1, conn2], tspan=(0.0, 1.0),
        timescales=[1, 1 // 60])

    mp2 = SirenProblem(
        components=[c1, c3], connectors=[conn1, conn2], tspan=(0.0, 1.0))

    alg = MinimumTimeStepper()
    sol1 = solve(mp1, alg)
    sol2 = solve(mp2, alg)

    # Floating point errors will stack together differently, which may cause an extra step in one of the solutions.
    a = [sol1(t)["Prey.prey"] for t in 0:0.01:1.0]
    b = [sol2(t)["Prey.prey"] for t in 0:0.01:1.0]
    @test all(a .≈ b)
    @test sol1.t[1:min(length(sol1.t), length(sol2.t))] ≈
          sol2.t[1:min(length(sol1.t), length(sol2.t))]
end

@testitem "siren problem constructor" begin
    using OrdinaryDiffEq
    using OrdinaryDiffEqLowOrderRK

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
    u0 = [4.0, 2.0]
    tspan = (0.0, 1.0)
    prob1 = ODEProblem(f1!, [u0[1], 2.0], tspan)
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

    # Tspan as a vector
    sp = SirenProblem(
        components=[c1, c2], connectors=[conn1, conn2], tspan=[0.0, 1.0])

    # empty connectors
    sp = SirenProblem(
        components=[c1, c2], connectors=[], tspan=(0.0, 1.0))

    # empty components
    sp = SirenProblem(
        components=[], connectors=[conn1, conn2], tspan=(0.0, 1.0))

    # duplicate component names
    c3 = DEComponent(
        prob2, Euler();
        name="Predator",
        timestep=0.002,
        state_names=OrderedDict("predator" => 1, "prey" => 2),
        intkwargs=(; adaptive=false, dt=0.002)
    )
    @test_throws ErrorException SirenProblem(
        components=[c1, c2, c3], connectors=[conn1, conn2], tspan=(0.0, 1.0))

    # tuple timescales
    sp = SirenProblem(
        components=[c1, c2], connectors=[conn1, conn2], tspan=(0.0, 1.0), timescales=(1.0, 2.0))

    # tspan too short
    @test_throws ArgumentError SirenProblem(
        components=[c1, c2], connectors=[conn1, conn2], tspan=[0.0])

    # non-kwarg constructor
    sp = SirenProblem([c1, c2], [conn1, conn2], (0.0, 1.0))
    sp = SirenProblem([c1, c2], [conn1, conn2], [0.0, 1.0], [1.0, 1.0])
end

@testitem "connectors" begin
    @test ConnectedVariable("comp", "var", [1, 2, 3], [4, 5]) == ConnectedVariable("comp[[4,5]].var[[1,2,3]]")
    @test ConnectedVariable("comp", "var", [1, 2, 3], nothing) == ConnectedVariable("comp.var[[1,2,3]]")
    @test ConnectedVariable("comp", "var", nothing, [4, 5]) == ConnectedVariable("comp[[4,5]].var")
    @test ConnectedVariable("comp", "var", nothing, nothing) == ConnectedVariable("comp.var")

    @test ConnectedVariable("comp.var[1:3]") == ConnectedVariable("comp.var[[1,2,3]]")

    @test Connector((ConnectedVariable("comp1.var1"), ConnectedVariable("comp2.var2")),
        (ConnectedVariable("comp3.var3"), ConnectedVariable("comp4.var4"))) ==
          Connector(["comp1.var1", "comp2.var2"], ["comp3.var3", "comp4.var4"])

    @test Connector((ConnectedVariable("comp1.var1"), ConnectedVariable("comp2.var2")),
        (ConnectedVariable("comp3.var3"), ConnectedVariable("comp4.var4"))) ==
          Connector(("comp1.var1", "comp2.var2"), ("comp3.var3", "comp4.var4"))

end
