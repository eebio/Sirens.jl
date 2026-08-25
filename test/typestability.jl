@testitem "JET - Package" begin
    using JET
    if VERSION >= v"1.12" && JET.JET_AVAILABLE
        test_package(Sirens; target_modules=(Sirens,))
    end
end

@testitem "JET - instabilities" begin
    using JET
    using Agents, OrdinaryDiffEq
    using Random

    if VERSION >= v"1.12" && JET.JET_AVAILABLE
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
            (agent_step!)=schelling_step!, properties
        )

        for n in 1:300
            add_agent_single!(model; group=n < 300 / 2 ? 1 : 2)
        end

        c1 = AgentsComponent(model;
            name="Schelling",
            state_names=OrderedDict("min_to_be_happy" => :min_to_be_happy),
            timestep=1.0
        )

        function f2(u, p, t)
            return 2 * 1 / 8 * cos(t / 8)
        end
        u0 = 3.0
        tspan = (0.0, 100.0)
        prob = ODEProblem(f2, u0, tspan)
        c2 = DEComponent(
            prob, Tsit5();
            name="ode",
            timestep=1.0,
            state_names=OrderedDict("happy" => 1),
            intkwargs=(; dt=1.0)
        )

        conn = Connector(
            inputs=["ode.happy"],
            outputs=["Schelling.min_to_be_happy"]
        )

        sp = SirenProblem(components=[c1, c2], connectors=[conn], tspan=(0.0, 100.0))

        alg = MinimumTimeStepper()
        sirenInt = init(sp, alg)

        # Test for type stability performance
        @test_opt AgentsComponent(model;
            name="Schelling",
            state_names=OrderedDict("min_to_be_happy" => :min_to_be_happy),
            timestep=1.0
        )

        @test_opt DEComponent(
            prob, Tsit5();
            name="ode",
            timestep=1.0,
            state_names=OrderedDict("happy" => 1),
            intkwargs=(; dt=1.0)
        )

        r = @report_opt Connector(["ode.happy"], ["Schelling.min_to_be_happy"])
        # ConnectedVariable type can't be fully inferred (variable and duplicated index)
        @test length(JET.get_reports(r)) > 0
        a = ConnectedVariable("ode.happy")
        b = ConnectedVariable("Schelling.min_to_be_happy")
        @test_opt Connector((a,), (b,))
        # Or no instability if you use a full constructor rather than a string constructor with tuples
        @test_opt Connector((ConnectedVariable("ode", "happy", nothing, nothing)), (ConnectedVariable("Schelling", "min_to_be_happy", nothing, nothing)))

        @test_opt SirenProblem((c1, c2), (conn,), (0.0, 100.0)) broken = true
        # But return type is correctly inferred
        types = Base.return_types(SirenProblem, (typeof((c1, c2)), typeof((conn,)), typeof((0.0, 100.0))))
        @test isconcretetype(types[1])

        # Tuples for save_vars are type stable
        @test_opt init(sp, alg; save_vars=())
        @test_opt init(sp, alg; save_vars=(a, b))
        #=
        The following things are expected/known to be type unstable in solve!:
        - The creation of a SirenSolutionData object cannot infer the types of the values at compile time
        - Saving variables with deepcopy in update_solution!
        - The return value of getstate (and therefore the input value of setstate! in runconnection!)
        - @assert in step! for floating point comparison of times
        =#
        @test_opt solve!(sirenInt) broken=true
    end
end
