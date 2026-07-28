# Mermaid Interface

In this section, we will:

* See the integrator interface that Mermaid uses,
* Find out how this fits with [CommonSolve](@extref CommonSolve index).

## Interface requirements

The interface used in Mermaid is compatible with, and uses, the SciML [CommonSolve](@extref CommonSolve index) interface.
In particular, each Component is some immutable problem type that stores required data to solve a Component (for example, an [ODEProblem](@extref DiffEq types/ode_types)).
We then also have an Integrator for each Component which stores the current state and handles solving over time.

## Component

A component should be immutable and store all of the information required to solve a given sub-problem/model:

It should also have implementations of the following functions:

```@docs; canonical=false
name
timestep
variables
```

If the component has fields for `name` and `timestep`, then those functions don't need to be implemented.

## Integrator

A `ComponentIntegrator` is a mutable struct which can be freely modified over a simulation, since it will be typically discarded at the end.
It only stores the current state of that component, and has some associated functions for handling this state.

## Functions

Most of the interface for Mermaid is built around functions that manipulate the integrator state.

### `step!`

The `step!` function should advance the `ComponentIntegrator` one time step (defined by `timestep(ComponentIntegrator)`).

```@docs; canonical=false
step!
```

### init

The `init` function takes as inputs a `Component` and returns the corresponding `ComponentIntegrator`.

```@docs; canonical=false
init
```

### `getstate` and `setstate!`

The function `getstate` reads the state of an `AbstractComponentIntegrator` at a given `ConnectedVariable` and returns it.
The `setstate!` function similarly mutates the current state of the `ComponentIntegrator` to assign an inputted value to the `ConnectedVariable`.
Additionally, `getstate` and `setstate!` should have methods that do not take a `ConnectedVariable`, and instead return the full state (in a form that should be compatible between the two functions, but need not be documented).

The function signatures should be `getstate(integrator, variable)/setstate!(integrator, variable, value)` and `getstate(integrator)/setstate!(integrator, state)`.

```@docs; canonical=false
getstate
setstate!
```

### `gettime` and `settime!`

Simply returns the current simulated time of a `ComponentIntegrator`. Defaults to calling `getstate` and `setstate!` with the special variable `"#time"`.

These functions don't need to be defined for new components, but `getstate` and `setstate!` should handle the `"#time"` special variable.

```@docs; canonical=false
gettime
settime!
```

### Other functions

The interface for a `Component` is also required to be satisfied for a `ComponentIntegrator`. That is, implementations of `name`, `timestep`, and `variables` should exist.

If the `ComponentIntegrator` has a field/property for the `Component` called `component`, then these functions don't need new implementations.

## Variable Names

Mermaid has its own interface for connections too.
A [Connector](@ref) uses instances of [ConnectedVariables](@ref ConnectedVariable) as part of applying the connections.
If you want to write your own components, it is worth learning how the [ConnectedVariables](@ref ConnectedVariable) are defined.

```@docs; canonical=false
ConnectedVariable
```

We can see that each `ConnectedVariable` has two names, the first is the component name and the second is the variable name (which should match `state_names` for that component).

It also has a variable index, which allows you to access only some parts of a full vector. For example, you may index on only some agents in an AgentsComponent.

Finally, it has a duplicated index. Like the variable index, it allows you to act on some subset, but in this case, it is a subset of integrators from a [DuplicatedComponent](@ref).

A `ConnectedVariable` can also be constructed from a single string input, ie `ConnectedVariable("component[duplicatedindex].variable[variableindex]")`.

```@docs; canonical=false
ConnectedVariable(::AbstractString)
```

## Examples

To see some examples, look in the `ext` directory on GitHub.
