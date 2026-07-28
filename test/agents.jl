@testitem "agent" begin
    using Agents, OrdinaryDiffEq
    using Random
    Random.seed!(1234)

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

    properties = Dict(:min_to_be_happy => 3.0)

    model = StandardABM(
        Schelling,
        space;
        (agent_step!) = schelling_step!, properties
    )

    for n in 1:300
        add_agent_single!(model; group = n < 300 / 2 ? 1 : 2)
    end

    c1 = AgentsComponent(model;
        name = "Schelling",
        state_names = OrderedDict("min_to_be_happy" => :min_to_be_happy),
        timestep = 1.0
    )

    function f2(u, p, t)
        return 2 * 1 / 8 * cos(t / 8)
    end
    u0 = 3.0
    tspan = (0.0, 100.0)
    prob = ODEProblem(f2, u0, tspan)
    c2 = DEComponent(
        prob, Tsit5();
        name = "ode",
        timestep = 1.0,
        state_names = OrderedDict("happy" => 1),
        intkwargs = (:dt => 1.0,)
    )

    conn = Connector(
        inputs = ["ode.happy"],
        outputs = ["Schelling.min_to_be_happy"]
    )

    mp = MermaidProblem(components = [c1, c2], connectors = [conn], tspan = (0.0, 100.0))

    alg = MinimumTimeStepper()
    intMer = init(mp, alg)
    solMer = solve!(intMer)

    @test solMer["ode.happy"][1:(end - 1)] == solMer["Schelling.min_to_be_happy"][2:end]

    intMer = init(mp, alg)
    for _ in 1:10
        step!(intMer)
    end
    # Early on, min_to_be_happy is high, so lots of agents moving
    pos = [intMer.integrators[1].integrator[i].pos for i in 1:300]
    step!(intMer)
    pos2 = [intMer.integrators[1].integrator[i].pos for i in 1:300]
    @test any(pos != pos2)
    for _ in 1:35
        step!(intMer)
    end
    # Later, min_to_be_happy is low, so agents aren't moving
    pos3 = [intMer.integrators[1].integrator[i].pos for i in 1:300]
    step!(intMer)
    pos4 = [intMer.integrators[1].integrator[i].pos for i in 1:300]
    @test all(pos3 == pos4)
    # And all agents are happy
    @test all([intMer.integrators[1].integrator[i].mood for i in 1:300])
end

@testitem "state control" begin
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

    properties = Dict(:min_to_be_happy => 3.0, :list_property => [1, 2, 3])

    model = StandardABM(
        Schelling,
        space;
        (agent_step!) = schelling_step!, properties
    )

    for n in 1:300
        add_agent_single!(model; group = n < 300 / 2 ? 1 : 2)
    end

    c1 = AgentsComponent(model;
        name = "Schelling",
        state_names = OrderedDict("min_to_be_happy" => :min_to_be_happy,
            "list_property" => :list_property, "mood" => :mood, "group" => :group),
        timestep = 0.2
    )

    conn1 = Connector(
        inputs = ["Schelling.min_to_be_happy"],
        outputs = ["other.min_to_be_happy"]
    )
    conn2 = Connector(
        inputs = ["other.min_to_be_happy"],
        outputs = ["Schelling.group[1:300]"]
    )

    integrator = init(c1)

    @test issetequal(variables(integrator),
        ["min_to_be_happy", "group", "mood", "list_property", "#model", "#time", "#ids"])

    # Check initial state
    @test getstate(integrator, ConnectedVariable("Schelling.min_to_be_happy")) == 3.0
    @test getstate(integrator, ConnectedVariable("Schelling.group")) ==
          [n < 300 / 2 ? 1 : 2 for n in allids(integrator.integrator)]
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ==
          [false for _ in allids(integrator.integrator)]
    # Check setting state
    setstate!(integrator, ConnectedVariable("Schelling.min_to_be_happy"), 5.0)
    @test getstate(integrator, ConnectedVariable("Schelling.min_to_be_happy")) == 5.0
    @test getstate(integrator, ConnectedVariable("Schelling.group")) ==
          [n < 300 / 2 ? 1 : 2 for n in allids(integrator.integrator)]
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ==
          [false for _ in allids(integrator.integrator)]

    setstate!(integrator, ConnectedVariable("Schelling.group[1:3]"), [3, 4, 5])
    setstate!(integrator, ConnectedVariable("Schelling.mood[2:3]"), [true, true])
    setstate!(integrator, ConnectedVariable("Schelling.mood[300]"), true)
    @test getstate(integrator, ConnectedVariable("Schelling.min_to_be_happy")) == 5.0
    @test getstate(integrator, ConnectedVariable("Schelling.group")) ==
          [n ∈ [1, 2, 3] ? n + 2 : (n < 300 / 2 ? 1 : 2)
           for n in allids(integrator.integrator)]
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ==
          [n ∈ [2, 3, 300] ? true : false for n in allids(integrator.integrator)]
    @test getstate(integrator, ConnectedVariable("Schelling.mood[300]")) == true

    # Check time control (can't set time in Agents.jl)
    @test gettime(integrator) == 0.0
    step!(integrator)
    @test gettime(integrator) == 0.2

    # Step means the state has changed
    @test getstate(integrator, ConnectedVariable("Schelling.group")) ≠
          [3, 4, 5, [n < 300 / 2 ? 1 : 2 for n in 4:300]...]
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ≠
          [false, true, true, [false for _ in 4:300]..., true]

    setstate!(integrator, ConnectedVariable("Schelling.mood"),
        [true for _ in allids(integrator.integrator)])
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ==
          [true for _ in allids(integrator.integrator)]
    setstate!(integrator, ConnectedVariable("Schelling.list_property"), [4, 5, 6])
    @test getstate(integrator, ConnectedVariable("Schelling.list_property")) == [4, 5, 6]
    setstate!(integrator, ConnectedVariable("Schelling.list_property[1:2]"), [7, 8])
    @test getstate(integrator, ConnectedVariable("Schelling.list_property[1]")) == 7
    @test getstate(integrator, ConnectedVariable("Schelling.list_property[1:3]")) ==
          [7, 8, 6]

    # getstate and setstate! for duplicated AgentsComponent
    # abmtime is part of the state, not Mermaid's time control
    @test getstate(integrator) isa StandardABM
    @test gettime(integrator) ≈ 0.2
    state = getstate(integrator; copy = true) # Get a copy of the state
    state2 = getstate(integrator) # Default is don't copy, just return reference
    state3 = getstate(integrator; copy = false)
    step!(integrator)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.4
    setstate!(integrator, state)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.2
    setstate!(integrator, state2)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.4
    setstate!(integrator, state3)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.4

    settime!(integrator, 1.0)
    @test gettime(integrator) == 1.0
    step!(integrator)
    @test gettime(integrator) == 1.2

    # Same thing but with the #model variable
    @test getstate(integrator, ConnectedVariable("Schelling.#model")) isa StandardABM
    state = getstate(integrator, ConnectedVariable("Schelling.#model"); copy = true)
    step!(integrator)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.8
    setstate!(integrator, ConnectedVariable("Schelling.#model"), state)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.6
end

@testitem "state control - properties = struct" begin
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

    mutable struct props
        min_to_be_happy::Float64
        list_property::Vector{Int}
    end
    properties = props(3.0, [1, 2, 3])

    model = StandardABM(
        Schelling,
        space;
        (agent_step!) = schelling_step!, properties
    )

    for n in 1:300
        add_agent_single!(model; group = n < 300 / 2 ? 1 : 2)
    end

    c1 = AgentsComponent(model;
        name = "Schelling",
        state_names = OrderedDict("min_to_be_happy" => :min_to_be_happy,
            "list_property" => :list_property, "mood" => :mood, "group" => :group),
        timestep = 0.2
    )

    conn1 = Connector(
        inputs = ["Schelling.min_to_be_happy"],
        outputs = ["other.min_to_be_happy"]
    )
    conn2 = Connector(
        inputs = ["other.min_to_be_happy"],
        outputs = ["Schelling.group[1:300]"]
    )

    integrator = init(c1)

    @test issetequal(variables(integrator),
        ["min_to_be_happy", "group", "mood", "list_property", "#model", "#time", "#ids"])

    # Check initial state
    @test getstate(integrator, ConnectedVariable("Schelling.min_to_be_happy")) == 3.0
    @test getstate(integrator, ConnectedVariable("Schelling.group")) ==
          [n < 300 / 2 ? 1 : 2 for n in allids(integrator.integrator)]
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ==
          [false for _ in allids(integrator.integrator)]
    # Check setting state
    setstate!(integrator, ConnectedVariable("Schelling.min_to_be_happy"), 5.0)
    @test getstate(integrator, ConnectedVariable("Schelling.min_to_be_happy")) == 5.0
    @test getstate(integrator, ConnectedVariable("Schelling.group")) ==
          [n < 300 / 2 ? 1 : 2 for n in allids(integrator.integrator)]
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ==
          [false for _ in allids(integrator.integrator)]

    setstate!(integrator, ConnectedVariable("Schelling.group[1:3]"), [3, 4, 5])
    setstate!(integrator, ConnectedVariable("Schelling.mood[2:3]"), [true, true])
    setstate!(integrator, ConnectedVariable("Schelling.mood[300]"), true)
    @test getstate(integrator, ConnectedVariable("Schelling.min_to_be_happy")) == 5.0
    @test getstate(integrator, ConnectedVariable("Schelling.group")) ==
          [n ∈ [1, 2, 3] ? n + 2 : (n < 300 / 2 ? 1 : 2)
           for n in allids(integrator.integrator)]
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ==
          [n ∈ [2, 3, 300] ? true : false for n in allids(integrator.integrator)]
    @test getstate(integrator, ConnectedVariable("Schelling.mood[300]")) == true

    # Check time control (can't set time in Agents.jl)
    @test gettime(integrator) == 0.0
    step!(integrator)
    @test gettime(integrator) == 0.2

    # Step means the state has changed
    @test getstate(integrator, ConnectedVariable("Schelling.group")) ≠
          [3, 4, 5, [n < 300 / 2 ? 1 : 2 for n in 4:300]...]
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ≠
          [false, true, true, [false for _ in 4:300]..., true]

    setstate!(integrator, ConnectedVariable("Schelling.mood"),
        [true for _ in allids(integrator.integrator)])
    @test getstate(integrator, ConnectedVariable("Schelling.mood")) ==
          [true for _ in allids(integrator.integrator)]
    setstate!(integrator, ConnectedVariable("Schelling.list_property"), [4, 5, 6])
    @test getstate(integrator, ConnectedVariable("Schelling.list_property")) == [4, 5, 6]
    setstate!(integrator, ConnectedVariable("Schelling.list_property[1:2]"), [7, 8])
    @test getstate(integrator, ConnectedVariable("Schelling.list_property[1]")) == 7
    @test getstate(integrator, ConnectedVariable("Schelling.list_property[1:3]")) ==
          [7, 8, 6]

    # getstate and setstate! for duplicated AgentsComponent
    # abmtime is part of the state, not Mermaid's time control
    @test getstate(integrator) isa StandardABM
    @test gettime(integrator) ≈ 0.2
    state = getstate(integrator; copy = true) # Get a copy of the state
    state2 = getstate(integrator) # Default is don't copy, just return reference
    state3 = getstate(integrator; copy = false)
    step!(integrator)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.4
    setstate!(integrator, state)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.2
    setstate!(integrator, state2)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.4
    setstate!(integrator, state3)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.4

    settime!(integrator, 1.0)
    @test gettime(integrator) == 1.0
    step!(integrator)
    @test gettime(integrator) == 1.2

    # Same thing but with the #model variable
    @test getstate(integrator, ConnectedVariable("Schelling.#model")) isa StandardABM
    state = getstate(integrator, ConnectedVariable("Schelling.#model"); copy = true)
    step!(integrator)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.8
    setstate!(integrator, ConnectedVariable("Schelling.#model"), state)
    @test abmtime(getstate(integrator))*timestep(integrator) ≈ 0.6
end
