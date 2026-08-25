# Algebraic loops

## What is an algebraic loop?

A [Connector](@ref) says "read these input variables, apply a connection function, and write to these output variables".
When you have multiple connectors, they can read these output variables and apply further modifications to the system.
It is possible for a variable to depend on itself through these connections.
This is called an *algebraic loop*.

This is not necessarily a problem, but it is something to consider when constructing a [SirenProblem](@ref).
Sirens only applies the connections in the order specified in the [SirenProblem](@ref).

## Detecting loops

Because algebraic loops are a structural property of a set of connectors, Sirens checks for them when a [SirenProblem](@ref) is constructed.
The check builds the variable graph described above from every connector in the problem and looks for cycles.
If any are found, construction still succeeds, but a warning is emitted listing the offending variable cycle(s), since a loop is not always a mistake.

### Example warning

Constructing a [SirenProblem](@ref) containing an algebraic loop in its connections produces a warning like:

```julia
┌ Warning: Algebraic loop(s) detected in the following connections:
│ Cycle: comp.x -> comp2.y -> comp.z -> comp.x 
└ @ Sirens ~/.julia/dev/Sirens/src/loops.jl:40
```

## ImplicitConnector

There are some parts of Sirens that allow you to make implicit connections without it being obvious from the inputs and outputs of a [Connector](@ref).

```@example
using Sirens
function f!(integrator)
    integrator.u[2] += 1.0
end
conn = Connector(inputs = ["comp.#integrator"], outputs = String[], func = f!)

nothing #hide
```

This connector mutates the integrator, which changes one of the variables (`u[2]`), but that is not clear from the connections outputs.
This would not be caught by the algebraic loop detection in Sirens.
You can get a similar effect with other special variables like `#state` or `#ids` in a [DuplicatedComponent](@ref).

!!! note "#ids in DuplicatedComponent"
    When `#ids` is set in a [DuplicatedComponent](@ref), the system is immediately changed.
    If new ids are added, then the state is immediately updated.
    This means that setting `#ids` always results in implicit connections, although Sirens will need these to be added by the user to the connection list of the [SirenProblem](@ref).

Since special variables like `#integrator` and `#state` hide which physical variables they actually touch, the variable graph built from ordinary [Connector](@ref)s alone can miss real loops that pass through them.
[ImplicitConnector](@ref) lets you fill in that gap: it has the same `inputs`/`outputs` shape as a [Connector](@ref), so you can declare, for example, that there is a connection between `#integrator` and `u[2]`.

```julia
implicit = ImplicitConnector(inputs=["comp.#integrator"], outputs=["comp.u2"])
```

Unlike a [Connector](@ref), an [ImplicitConnector](@ref) is never applied during simulation - it contributes edges to the variable graph for loop detection only.
