@testitem "duplicated component" begin
    using OrdinaryDiffEq
    using Statistics

    function tree!(du, u, p, t)
        x, y = u
        du[1] = 0
        du[2] = y * (1 - y / 10.0) - x * y
    end
    u0 = [4.0, 2.0]
    tspan = (0.0, 10.0)
    prob = ODEProblem(tree!, u0, tspan)

    comp1 = DEComponent(
        prob, Rodas5P();
        name = "tree",
        state_names = OrderedDict("heat" => 1, "life" => 2)
    )
    dup_comp = DuplicatedComponent(comp1, [copy(u0) for _ in 1:640]; instances = 640)

    using Agents, Random
    @agent struct Tree(GridAgent{2})
        heat::Float64 # Heat is averaged across neighbors, passed to ODE model
        life::Float64 # Life is informed by ODE model
    end

    function forest_fire(; density = 0.4, griddims = (40, 40), seed = 2)
        space = GridSpaceSingle(griddims; periodic = false, metric = :chebyshev)
        rng = Random.MersenneTwister(seed)
        forest = StandardABM(Tree, space; rng, (agent_step!) = tree_step!)
        for _ in 1:floor(density * prod(griddims))
            # Randomly place trees in the grid
            add_agent_single!(forest; heat = rand(), life = rand())
        end
        return forest
    end

    function tree_step!(tree, forest)
        nearbyheat = mean([getproperty(neighbor, :heat)
                           for neighbor in nearby_agents(tree, forest, 1)])
        if isnan(nearbyheat)
            nearbyheat = 0.0
        end
        tree.heat = tree.heat * 0.9 + nearbyheat * 0.1
        if rand(abmrng(forest)) < 1e-4 # Random chance of fire
            tree.heat = 10.0
        end
        # Simulate tree life cycle
        if tree.heat > 1.0 && tree.life > 0
            # Tree on fire
            tree.heat += 1.0
        else
            # Tree not on fire so heat disappates
            tree.heat -= 0.1
        end
        if tree.heat < 0.0
            tree.heat = 0.0
        end
    end

    forest = forest_fire()

    comp2 = AgentsComponent(forest;
        name = "forest",
        state_names = OrderedDict("heat" => :heat, "life" => :life)
    )

    conn1 = Connector(inputs = ["forest.heat[1:640]"], outputs = ["tree[1:640].heat"])
    conn2 = Connector(inputs = ["tree[1:640].life"], outputs = ["forest.life[1:640]"])

    mp = SirenProblem(
        components = [dup_comp, comp2], connectors = [conn1, conn2], tspan = (0.0, 10.0)
    )
    alg = MinimumTimeStepper()
    sol = solve(mp, alg)
end

@testitem "flexible duplicated component" begin
    using OrdinaryDiffEq
    using Agents
    using Statistics
    using Random

    # ODE: dval/dt = -val + val2
    function coupled!(du, u, p, t)
        du[1] = -u[1] + u[2]
        du[2] = 0
    end
    u0 = [1.0, 0.5]
    tspan = (0.0, 2.0)
    prob = ODEProblem(coupled!, u0, tspan)
    comp1 = DEComponent(
        prob, Rodas5P();
        name = "decay",
        state_names = OrderedDict("val" => 1, "val2" => 2)
    )

    @agent struct Dummy(GridAgent{2})
        val2::Float64
        val::Float64
    end

    function dummy_abm(; n = 3, griddims = (3, 1), seed = 1)
        space = GridSpace(griddims; periodic = false)
        rng = Random.MersenneTwister(seed)
        abm = StandardABM(Dummy, space; rng, (agent_step!) = dummy_step!)
        for i in 1:n
            add_agent!(abm; val2 = i, val = 0.0)
        end
        return abm
    end

    function dummy_step!(agent, model)
        # No-op, val will be set by ODE
    end

    abm = dummy_abm()
    comp2 = AgentsComponent(abm;
        name = "dummyabm",
        state_names = OrderedDict("val2" => :val2, "val" => :val)
    )

    # Flexible duplicated component: no instances specified
    dup_comp = DuplicatedComponent(comp1, []; default_state = [5.0, 1.0]
    ) # TODO How can we set the initial states to be different for each instance?

    # Connect agent ids to duplicated component ids, val2 to ODE, val from ODE to agent
    conn_ids = Connector(inputs = ["dummyabm.#ids"], outputs = ["decay.#ids"])
    conn_val2 = Connector(inputs = ["dummyabm.val2"], outputs = ["decay.val2"])
    conn_val = Connector(inputs = ["decay.val"], outputs = ["dummyabm.val"])

    mp = SirenProblem(
        components = [dup_comp, comp2],
        connectors = [conn_ids, conn_val2, conn_val],
        tspan = (0.0, 5.0)
    )
    alg = MinimumTimeStepper()

    int = init(mp, alg)
    step!(int)
    # Add new agent and check that the number of duplicated states matches the number of agents at each step
    add_agent!(int.integrators[2].integrator; val2 = 1.0, val = 0.0)
    step!(int)
    agent_int = int.integrators[2]
    dup_int = int.integrators[1]
    @test length(dup_int.states) == nagents(agent_int.integrator) == 4
    # Set the ids manually
    states = getstate(dup_int, ConnectedVariable("decay.val"))
    ids = getstate(dup_int, ConnectedVariable("decay.#ids"))
    setstate!(dup_int, ConnectedVariable("decay.#ids"), [1, 2, 5, 4])
    states2 = getstate(dup_int, ConnectedVariable("decay.val"))
    ids2 = getstate(dup_int, ConnectedVariable("decay.#ids"))
    @test issetequal(ids, [1, 2, 3, 4])
    @test states ≠ states2
    @test length(states2) == length(states) == 4
    @test ids2 == [1, 2, 5, 4]
    @test states[ids .== 1] == states2[ids2 .== 1]
    @test states[ids .== 2] == states2[ids2 .== 2]
    @test states[ids .== 4] == states2[ids2 .== 4]
    @test states[ids .== 3] ∉ states2
    @test states2[ids2 .== 5] == [5.0] # The new agent's value is set to the default state

    # Test deleting multiple ids
    setstate!(dup_int, ConnectedVariable("decay.#ids"), [1, 5])
    states3 = getstate(dup_int, ConnectedVariable("decay.val"))
    ids3 = getstate(dup_int, ConnectedVariable("decay.#ids"))
    @test ids3 == [1, 5]
    @test states3[ids3 .== 1] == states2[ids2 .== 1]
    @test states3[ids3 .== 5] == states2[ids2 .== 5]
    @test states3[ids3 .== 5] == [5.0]
    @test length(states3) == 2

    # init_states
    setstate!(dup_int, ConnectedVariable("decay.#states"), [[1.0, 0.5], [2.0, 1.5]])
    @test getstate(dup_int, ConnectedVariable("decay.#ids")) == [1, 5]
    setstate!(dup_int, ConnectedVariable("decay.#init_states"), Dict(10 => [10.0, 2.0]))
    @test getstate(dup_int, ConnectedVariable("decay.#init_states")) == Dict(10 => [10.0, 2.0])
    setstate!(dup_int, ConnectedVariable("decay.#ids"), [1, 3, 5, 10])
    @test getstate(dup_int, ConnectedVariable("decay.val")) == [1.0, 5.0, 2.0, 10.0]
    @test getstate(dup_int, ConnectedVariable("decay.val2")) == [0.5, 1.0, 1.5, 2.0]
    @test getstate(dup_int, ConnectedVariable("decay.#states")) == [[1.0, 0.5], [5.0, 1.0], [2.0, 1.5], [10.0, 2.0]]
    @test getstate(dup_int, ConnectedVariable("decay.#ids")) == [1, 3, 5, 10]

    # Add new agents doesnt break step!
    step!(int)

    @test getstate(dup_int, ConnectedVariable("decay.#ids")) ≠ [1, 3, 5, 10]

    # Check that solving isn't broken
    sol = solve(mp, alg)
end
