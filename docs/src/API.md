# API

## Contents

```@contents
Pages = ["API.md"]
Depth = 2:3
```

This page documents the public API and the execution model used by Mermaid.
The [Tutorial](@ref) is a narrative introduction; this page is a reference for understanding the structure and interfaces.

## Core concepts

A Mermaid simulation has four layers:

1. A **component** is an immutable description of a model and its configuration.
2. A **component integrator** is the mutable runtime state created from a component via `init(component)`.
3. A [`MermaidProblem`](@ref) stores components, connectors, the global time span, and component time scales.
4. A [`MermaidSolution`](@ref) stores selected variables at selected global times.

The typical workflow is:

```julia
prob = MermaidProblem(components=..., connectors=..., tspan=...)
sol = solve(prob, alg; save_vars=..., saveat=...)
```

The convenience function `solve` is provided by CommonSolve and performs initialization followed by solving.
For manual stepping, use `init(prob, alg)` to create a `MermaidIntegrator`, then call `step!` repeatedly or `solve!` to run to completion.

## Problems and algorithms

### `MermaidProblem`

```@docs
MermaidProblem
```

### `MermaidIntegrator`

```@docs
MermaidIntegrator
```

### Initialization and solving

```@docs
init(::AbstractMermaidProblem, ::AbstractMermaidSolver)
solve!
step!(::AbstractMermaidIntegrator)
```

### Solvers

```@docs
MinimumTimeStepper
```

## Connections

### Connected variables

```@docs
ConnectedVariable
ConnectedVariable(::AbstractString)
fullname
```

### Connectors

```@docs
Connector
ImplicitConnector
runconnection
runconnection!
```

## Timestepping and multirate solving

`MermaidProblem` accepts one `timescales` value per component. For component `i` with timescale $s_i$:

$$t_{global,i} = s_i \cdot t_{local,i}$$

A component with $s_i = 0.1$ advances ten local time units per one global time unit.

See the [`MinimumTimeStepper`](@ref) docstring for details on the stepping algorithm.

## Saving and solutions

### Saving options

Saving configuration is passed during `init` or `solve`:

```@docs; canonical=false
init(::AbstractMermaidProblem, ::AbstractMermaidSolver)
```

### `MermaidSolution`

```@docs
MermaidSolution
```

A solution has `sol.t` (saved global times) and `sol.u` (dictionary mapping variable names to saved states).

#### Solution indexing and interpolation

```@docs
Base.getindex(::AbstractMermaidSolution, ::AbstractString)
```

See the [`MermaidSolution`](@ref) docstring for details on interpolation behavior, including handling of numeric vs. non-numeric states.

## Components

All time-dependent components expose `name`, `timestep`, `variables`, `init`, `step!`, `getstate`, `setstate!`, `gettime`, and `settime!` through the common interface.
Each component type documents its special variables and specific behavior in its docstring.

### Differential Equations Components

```@docs
DEComponent
DEComponentIntegrator
```

### Agents Components

```@docs
AgentsComponent
AgentsComponentIntegrator
```

### MethodOfLines Components

```@docs
MOLComponent
MOLComponentIntegrator
```

### JumpProcesses Components

```@docs
JumpComponent
JumpComponentIntegrator
```

### TrixiParticles Components

```@docs
TrixiParticlesComponent
TrixiParticlesComponentIntegrator
```

### Surrogate Components

```@docs
SurrogateComponent
SurrogateComponentIntegrator
```

### [Duplicated Components](@id duplicatedComponentsAPI)

```@docs
DuplicatedComponent
DuplicatedComponentIntegrator
```

### Time-independent Components

```@docs
TimeIndependentComponent
```

## Abstract Types

These abstract types are extension points and are useful for method signatures:

```@docs
AbstractComponent
AbstractTimeDependentComponent
AbstractTimeIndependentComponent
AbstractComponentIntegrator
AbstractMermaidSolver
AbstractMermaidIntegrator
AbstractMermaidProblem
AbstractMermaidSolution
AbstractConnectedVariable
AbstractConnector
```

## User-Defined Components

One of the main goals of Mermaid is to make it simple and accessible to expand functionality with user-defined components.
This is done through the component interface—a set of functions that can be implemented to support all Mermaid functionality.

### Core interface functions

```@docs
name
timestep
variables
getstate
setstate!
gettime
settime!
step!(::AbstractComponentIntegrator)
init(::AbstractComponent)
```

### Implementing a custom component

To implement a custom component:

1. Define an immutable `struct MyComponent` to hold the configuration.
2. Define a `mutable struct MyComponentIntegrator` to hold runtime state.
3. Implement `init(::MyComponent)` to return a `MyComponentIntegrator`.
4. Implement `step!(integrator::MyComponentIntegrator)` to advance the state.
5. Implement `name`, `timestep`, and `variables` for both structs.
6. Implement `getstate` and `setstate!` to expose your component's variables.
7. Implement `gettime` and `settime!` to expose your component integrator's current time.

While there are quite a few functions here that need to be defined, the majority of them have default behaviour that you can opt in to.

* `name(integrator)`, `timestep(integrator)`, and `variables(integrator)` can use the default behavior of `name(integrator) = name(integrator.component)` (and other equivalents) if the component is stored as a property of the integrator.
* `timestep(component)` and `name(component)` can use the default behaviour of `component.timestep` and `component.name`, if the property or field exists.
* `gettime` and `settime!` will default to attempting to access the `#time` special variable of `getstate` and `setstate!`.
* `getstate` and `setstate!` do not need to implement any of the keyword argument features (i.e. `copy`).
