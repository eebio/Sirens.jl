# Duplicated Components

In this tutorial, we will introduce [DuplicatedComponents](@ref DuplicatedComponent).

The example system we will use for this will be a model of a forest fire (governed by an Agent-based model), with the growth of each tree informed by an ODE model.

## Components

To begin, we need to define our components. These will be an ODE model component for each tree, and an Agent-based model component for handling the forest level properties (in this case, the spread of heat/fire).

### ODE Component

To define a [DuplicatedComponent](@ref), we first need to define the component we want to duplicate. In this case, it is a [DEComponent](@ref).

```@example tutorial
using OrdinaryDiffEq
using Mermaid

function tree!(du, u, p, t)
    heat, life = u
    du[1] = 0
    du[2] = (life*(1-life/10.0)-heat*life)/10
end
u0 = [4.0, 2.0]
tspan = (0.0, 150.0)
prob = ODEProblem(tree!, u0, tspan)

comp1 = DEComponent(prob, Rodas5P();
    name="tree", state_names=Dict("heat" => 1, "life" => 2),
)

nothing #hide
```

### Duplicated Component

Since the `ODEProblem` is defined for only a single tree, we can efficiently simulate the same ODE system many times by generating a duplicated component.
This component stores a single `ODEProblem` that it will solve across many different states.
In this case, we can have a state for each tree in the Agent-based model.
Let's have a look at how to define a [DuplicatedComponent](@ref).

```@docs; canonical=false
DuplicatedComponent
```

```@example tutorial
dup_comp = DuplicatedComponent(comp1, [copy(u0) for _ in 1:640];
    instances=640,
)

nothing #hide
```

### Agents.jl Component

Now that we have created our [DEComponent](@ref), we can move on to the [AgentsComponent](@ref), so let's have a look at its documentation.

```@example tutorial
using Agents, Random, Statistics
@agent struct Tree(GridAgent{2})
    heat::Float64 # Heat is averaged across neighbors, passed to ODE model
    life::Float64 # Life is informed by ODE model
end

function forest_fire(; density=0.4, griddims=(40, 40), seed=2)
    space = GridSpaceSingle(griddims; periodic=false, metric=:chebyshev)
    rng = Random.MersenneTwister(seed)
    forest = StandardABM(Tree, space; rng, agent_step! = tree_step!)
    for _ in 1:floor(density * prod(griddims))
        # Randomly place trees in the grid
        add_agent_single!(forest; heat=rand(), life=rand())
    end
    return forest
end

function tree_step!(tree, forest)
    nearbyheat = mean([getproperty(neighbor, :heat) for neighbor in nearby_agents(tree, forest, 1)])
    if isnan(nearbyheat)
        nearbyheat = 0.0
    end
    tree.heat = tree.heat * 0.9 + nearbyheat * 0.1
    if rand(abmrng(forest)) < 1e-4 # Random chance of fire
        tree.heat = 10.0
    end
    # Simulate tree life cycle
    if tree.heat > 1.0 && tree.life > 1.0
        # Tree on fire
        tree.heat += 1.0
    else
        # Tree not on fire, so heat dissipates
        tree.heat -= 0.05
    end
    if tree.heat < 0.0
        tree.heat = 0.0
    end
end

forest = forest_fire()

comp2 = AgentsComponent(forest;
    name="forest", state_names=Dict("heat" => :heat, "life" => :life)
)
```

## Connections

We can now set up the connections between the variables in the two components.

```@docs; canonical=false
Connector
```

The format for specifying a [ConnectedVariable](@ref) is given in [Mermaid Interface](@ref), but in short, it is a string containing a component name and a variable/state name. It can also contain optional indices for only accessing part of a variable (given at the end of the ConnectedVariable), or for only accessing some subcomponents, such as for DuplicatedComponents (given at the end of the component name).

```@example tutorial
conn1 = Connector(inputs=["forest.heat[1:640]"], outputs=["tree[1:640].heat"])
conn2 = Connector(inputs=["tree[1:640].life"], outputs=["forest.life[1:640]"])
```

## Solving the hybrid model

To create the hybrid model, we need to create a [MermaidProblem](@ref).
We can then solve this using the `CommonSolve` interface.

```@docs; canonical=false
MermaidProblem
```

```@example tutorial
mp = MermaidProblem(components=[dup_comp, comp2], connectors=[conn1, conn2], tspan=tspan)
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

plot(sol.t, sol["forest.life[1]"], color=:green, label="Life")
plot!(sol.t, sol["forest.heat[1]"], color=:red, label="Heat")

nothing # hide
```

## Advanced Visualisations

While we can plot the variables from the ODE component easily, the Agent-based model is a bit more challenging.
By default, we only store the variables given in `state_names` in the solution.
This can be changed by providing `save_vars=["forest.#model"]` to `solve`, in which case the full agent-based model state will be visible in the solution at all time points.

!!! tip "#model and Special Variables"
    `"#model"` is a special variable for AgentsComponents. Special variables, denoted by starting with `#` are not saved by default but can be used with connectors, `getstate`, `setstate!`, or `save_vars`. To view the special variables of a component, you can call `variables(component)`.

However, this can be wasteful if we know we only want an animation of the model (which can be generated during simulation).
We will set up a [Connector](@ref) which takes an input of the model's current state, and instead of a transformation, we will use a function which adds the current state to a video.

```@example tutorial
using Makie
using CairoMakie

groupcolor(tree) = tree.heat > 1 ? :red : :green
groupmarker(a) = a.life > 1 ? :utriangle : :circle
fig, ax = abmplot(forest; agent_color=groupcolor, agent_marker=groupmarker, agent_size=10)
io = VideoStream(fig)
function plot_input(model)
    empty!(ax)
    abmplot!(ax, model; agent_color=groupcolor, agent_marker=groupmarker, agent_size=10)
    recordframe!(io)
end

conn3 = Connector(
    inputs=["forest.#model"],
    outputs=Vector{String}(),
    func=(model) -> plot_input(model)
)

mp = MermaidProblem(components=[dup_comp, comp2], connectors=[conn1, conn2, conn3], tspan=tspan)
sol = solve(mp, alg)

save("forest_fire.mp4", io)

nothing #hide
```

![An animation of the forest fire simulation](forest_fire.mp4)
