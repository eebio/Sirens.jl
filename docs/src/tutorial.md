# Tutorial

In this tutorial, we will:

* Create a hybrid simulation between an Agent-based model, defined in Agents.jl, and an ODE system defined through DifferentialEquations.jl.
* Introduce Mermaid Components for Agents.jl and DifferentialEquations.jl.
* Demonstrate how these Components can be connected together through Connectors.
* Solve the hybrid model.
* Visualise the results of the simulation.

This example will include a group of birds, flocking around some food at a single moving point, where the motion of the moving point is governed by an ODE system.

## Components

To begin, we need to define our components. These will be an ODE model component for the movement of the food, and an Agent-based model component for the birds.

### Differential Equations Components

To define the ODE model, let's have a look at how to define an ODE Component.

```@docs; canonical=false
DEComponent
```

We see that we need to define an `ODEProblem` to use in the component, so let's create one.

```@example tutorial
using OrdinaryDiffEq
function food!(du, u, p, t)
    x, y = u
    d = 10.0
    mu = 1.3
    tau = 30.0
    du[1] = (y - 50)/tau
    du[2] = (mu * (1 - (x-50)^2/d^2)*(y-50) - (x-50))/tau
end
u0 = [40.0, 40.0]
tspan = (0.0, 500.0)
prob = ODEProblem(food!, u0, tspan)

nothing #hide
```

Next, we want to wrap this ODEProblem inside an DEComponent.
For this, we will need to define the `state_names` field, and should generally provide a value for the `name` field (since component names in a hybrid simulation should be unique).

```@example tutorial
using Mermaid
comp1 = DEComponent(prob, Rodas5P();
    name="food", state_names=Dict("x" => 1, "y" => 2),
)

nothing #hide
```

### Agents.jl Components

Now that we have created our [DEComponent](@ref), we can move on to the [AgentsComponent](@ref), so let's have a look at its documentation.

```@docs; canonical=false
AgentsComponent
```

We can see that, again, we need to define the model (this time a `StandardABM` from `Agents.jl`), a `name` and a `state_names`.

```@example tutorial

using Agents, Random, LinearAlgebra
@agent struct Bird(ContinuousAgent{2, Float64})
    const speed::Float64
    const visual_distance::Float64
    const turn_speed::Float64
end

function initialize_model(;
        n_birds = 100,
        speed = 1.0,
        visual_distance = 15.0,
        turn_speed = 0.04,
        extent = (100, 100),
        seed = 0
)
    space2d = ContinuousSpace(extent)
    rng = Random.MersenneTwister(seed)

    props = Dict(:food_x => rand() * extent[1],
        :food_y => rand()*extent[2])

    model = StandardABM(
        Bird, space2d; rng, agent_step!, container = Vector, properties = props)
    for _ in 1:n_birds
        vel = rand(abmrng(model), SVector{2}) * 2 .- 1
        add_agent!(
            model,
            vel,
            speed,
            visual_distance,
            turn_speed
        )
    end
    return model
end

function agent_step!(bird, model)
    heading = get_direction(bird.pos, (model.food_x, model.food_y), model)

    if sum(heading .^ 2) < bird.visual_distance^2
        # Bird can see food so should head towards food
        bird.vel += bird.turn_speed * heading
    else
        # Bird can't see food so should turn towards nearest bird
        nearest_bird = nearest_neighbor(bird, model, bird.visual_distance)
        if !isnothing(nearest_bird)
            heading = get_direction(bird.pos, nearest_bird.pos, model)
        else
            heading = (0, 0)
        end
        bird.vel += bird.turn_speed * (heading .+ randn(abmrng(model), SVector{2}))
    end
    bird.vel /= norm(bird.vel)

    return move_agent!(bird, model, bird.speed)
end

model = initialize_model()

comp2 = AgentsComponent(model;
    name = "birds", state_names = Dict("x" => :food_x, "y" => :food_y)
)
```

## Connections

We can now set up the connections between the variables in the two components.

```@docs; canonical=false
Connector
```

The format for specifying a [ConnectedVariable](@ref) is given in [Mermaid Interface](@ref), but in its simplest form, it is a string containing a component name and a variable/state name.

```@example tutorial
conn1 = Connector(inputs=["food.x"], outputs=["birds.x"])
conn2 = Connector(inputs=["food.y"], outputs=["birds.y"])
```

## Solving the hybrid model

To create the hybrid model, we need to create a [MermaidProblem](@ref).
We can then solve this using the `CommonSolve` interface.

```@docs; canonical=false
MermaidProblem
```

```@example tutorial
mp = MermaidProblem(components=[comp1, comp2], connectors=[conn1, conn2], tspan=tspan)
alg = MinimumTimeStepper()
sol = solve(mp, alg)
```

## Plotting the solution

After running `solve`, we get `sol`, a [MermaidSolution](@ref) instance.
This stores all variables given in `state_names` at each timepoint.

```@docs; canonical=false
MermaidSolution
```

```@example tutorial
using Plots

plot(sol["food.x"], sol["food.y"], color=:green, label="Food trajectory")

nothing # hide
```

## Advanced Visualisations

While we can plot the variables from the ODE component easily, the Agent-based model is a bit more challenging.
By default, we only store the variables given in `state_names` in the solution.
This can be changed by providing `save_vars=["birds.#model"]` to `solve`, in which case the full agent-based model state will be visible in the solution at all time points.

!!! tip "#model and Special Variables"
    `"#model"` is a special variable for AgentsComponents. Special variables, denoted by starting with `#` are not saved by default but can be used with connectors, `getstate`, `setstate!`, or `save_vars`. To view the special variables of a component, you can call `variables(component)`.

However, this can be wasteful if we know we only want an animation of the model (which can be generated during simulation).
We will set up a [Connector](@ref) which takes an input of the model's current state, and instead of a transformation, we will use a function which adds the current state to a video.

```@example tutorial
using CairoMakie

const bird_polygon = Makie.Polygon(Point2f[(-1, -1), (2, 0), (-1, 1)])
function bird_marker(b::Bird)
    φ = atan(b.vel[2], b.vel[1]) #+ π/2 + π
    return rotate_polygon(bird_polygon, φ)
end

fig, ax = abmplot(model; agent_marker = bird_marker)
CairoMakie.scatter!(ax, [model.food_x], [model.food_y], markersize = 35, color = :green)
io = VideoStream(fig)
function plot_input(model)
    empty!(ax)
    abmplot!(
        ax, model; agent_marker = bird_marker)
    CairoMakie.scatter!(ax, [model.food_x], [model.food_y], markersize = 35, color = :green)
    recordframe!(io)
end

conn3 = Connector(
    inputs = ["birds.#model"],
    outputs = Vector{String}(),
    func = (model) -> plot_input(model)
)

mp = MermaidProblem(components = [comp1, comp2], connectors = [conn1, conn2, conn3], tspan = tspan)
sol = solve(mp, alg)

save("birds.mp4", io)

nothing #hide
```

![An animation of the bird-food simulation](birds.mp4)
