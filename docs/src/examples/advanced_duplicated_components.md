# Advanced Duplicated Components

You may have seen us use duplicated components in the [Tutorial](@ref).
This is a very powerful tool that lets you efficiently create many instances of a component integrator, each with their own state that can be stepped independently.
In the [Tutorial](@ref), we used duplicated components to create lots of instances of the tree ODE model, so every tree could be tracked independently.
Rather than creating 640 components, each with its own integrator - we create 640 state vectors, reducing the memory requirements for the duplicated component.

However, while this functionality is useful, it is not always possible to specify the number of instances *a priori*.
For example, we may have wanted trees that die to be removed from the simulation, or new trees to be created over time.

For this reason, it is also possible to create duplicated components with a variable/unknown number of instances.

## Setup

For this example, we are going to create an agent-based model of a cell population with each cell governed by a simple growth model tracking protein mass, which depends on a spatial nutrient distribution and the number of nearby cells.

```@example dupcomp
using OrdinaryDiffEq, Agents, Random, Mermaid, CairoMakie
using LinearAlgebra: norm
Random.seed!(1) # hide

function cell!(du, u, p, t)
    nutrients = u[1]
    du[1] = 0
    uptake = 2 * nutrients / (1 + nutrients)
    decay = 0.1 * (1+u[2]/10)
    du[2] = uptake - decay
end

u0 = [1.0, 1.0]
tspan = (0.0, 250.0)
prob = ODEProblem(cell!, u0, tspan)
using Mermaid
comp1 = DEComponent(prob, Rodas5P();
    name="cell", state_names=Dict("nutrients" => 1, "mass" => 2),
)

@agent struct Cell(ContinuousAgent{2,Float64})
    mass::Float64 # Cell mass is informed by ODE model
    nutrients::Float64 # Local nutrient availability
end

function colony(; n_cells=3, n_nodes=5, griddims=(40, 40), seed=2)
    space = ContinuousSpace(griddims; periodic=true)
    rng = Random.MersenneTwister(seed)
    nodes = [rand(2) .* griddims for _ in 1:n_nodes]
    colony = StandardABM(Cell, space; rng, (agent_step!)=cell_step!, properties=Dict(:nodes => nodes))
    for _ in 1:n_cells
        vel = rand(2) .- 0.5
        mass = rand()
        nutrients = rand()
        add_agent!(colony, vel, 1, 1)
    end
    return colony
end

function wrap_periodic(pos, dims)
    return SVector{length(pos)}(mod.(pos, dims))
end

function periodic_distance(a, b, dims)
    # Computes minimum image distance between points a and b in periodic box of size dims
    d = abs.(a .- b)
    return norm(min.(d, dims .- d))
end

function nutrients(pos, colony)
    nutrients = 0.0
    spread = 7.0
    dims = abmspace(colony).extent
    for node in colony.nodes
        # Calculate periodic distance to node
        dist = periodic_distance(node, pos, dims)
        nutrients += exp(-dist^2 / spread^2)/2 # Gaussian decay
    end
    return nutrients
end

function cell_step!(cell, colony)
    # Move away from nearby agents
    speed = 0.5
    for cell2 in nearby_agents(cell, colony, 0.5)
        cell.vel -= speed * (cell2.pos - cell.pos) / norm(cell2.pos - cell.pos)^2
    end
    # Max speed
    if norm(cell.vel) > speed
        cell.vel = speed * cell.vel / norm(cell.vel)
    end
    # Walk and apply chemotaxis
    oldnutrients = nutrients(cell.pos, colony)
    walk!(cell, cell.vel, colony)
    newnutrients = nutrients(cell.pos, colony)
    if newnutrients < oldnutrients
        # If nutrients decrease, random direction on next iteration
        cell.vel += rand(2) .- 0.5
    end
    # Update nutrients of cell, sharing between neighboring
    cell.nutrients = nutrients(cell.pos, colony)/(length(collect(nearby_ids(cell, colony, 0.5)))+1)
    # If large mass, split into two
    splitmass = 15
    if cell.mass > splitmass
        dims = abmspace(colony).extent
        for m in (splitmass/2, cell.mass - splitmass/2)
            new_pos = wrap_periodic(cell.pos + rand(2) .- 0.5, dims)
            add_agent!(new_pos, colony; vel=cell.vel, mass=m, nutrients=0)
        end
        remove_agent!(cell, colony)
    end
    if cell.mass < 0
        remove_agent!(cell, colony)
    end
end

pop = colony()

comp2 = AgentsComponent(pop;
    name="colony", state_names=Dict("mass" => :mass, "nutrients" => :nutrients)
)

conn1 = Connector(inputs=["colony.nutrients"], outputs=["cell.nutrients"])
conn2 = Connector(inputs=["cell.mass"], outputs=["colony.mass"])

nothing # hide
```

## Flexible Duplicated Components

If we don't provide any value for the `instances` field when creating the duplicated component, it will be created as a flexible duplicated component, letting a special input called `#ids` give the indexes of the current states (any indexes not specified in `#ids` are removed, and any state indexes specified in `#ids` that are not current states are created).
Some components, like AgentComponents, already have pre-made special outputs for the `#ids` which we can use to couple duplicated components to an Agent-based model.

```@example dupcomp
dup_comp = DuplicatedComponent(comp1, [];
    default_state=u0,
)
conn3 = Connector(inputs=["colony.#ids"], outputs=["cell.#ids"])

nothing # hide
```

!!! note "Sorting of Connectors"
    You may wonder about the order that connectors are applied. If we adjusted the IDs after applying `conn2`, we would be using an old value for IDs. Generally, we utilise the order specified in the MermaidProblem. For this reason, the `#ids` from `conn3` is applied first, as will be specified in the order of the connectors vector.

## Solving and visualisation

```@example dupcomp
function make_nutrient_heatarray(colony; gridsize=(40, 40))
    arr = zeros(Float64, gridsize...)
    xs = range(0, stop=abmspace(colony).extent[1], length=gridsize[1])
    ys = range(0, stop=abmspace(colony).extent[2], length=gridsize[2])
    for (i, x) in enumerate(xs), (j, y) in enumerate(ys)
        arr[i, j] = nutrients(SVector(x, y), colony)
    end
    return arr
end

fig, ax = abmplot(pop; agent_color=:black, agent_marker=:circle, agent_size=x->x.mass+3,
    heatarray=make_nutrient_heatarray, heatkwargs=(colormap=:Greens_5,))
io = VideoStream(fig; framerate=10)
function plot_input(model)
    empty!(ax)
    abmplot!(ax, model; agent_color=:black, agent_marker=:circle, agent_size=x -> x.mass + 3,
        heatarray=make_nutrient_heatarray, heatkwargs=(colormap=:Greens_5,))
    ax.title = "Time: $(round(abmtime(model))), Population: $(nagents(model))"
    recordframe!(io)
end

conn4 = Connector(
    inputs=["colony.#model"],
    outputs=Vector{String}(),
    func=(model) -> plot_input(model)
)

mp = MermaidProblem(components=[dup_comp, comp2], connectors=[conn3, conn1, conn2, conn4], tspan=tspan)
alg = MinimumTimeStepper()
sol = solve(mp, alg)

save("cell_colony.mp4", io)

nothing # hide
```

![An animation of the cell colony simulation](cell_colony.mp4)
