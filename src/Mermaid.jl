module Mermaid
@doc read(joinpath(dirname(@__DIR__), "README.md"), String) Mermaid

# Imports, Usings and Reexports
import CommonSolve: solve!, solve, init, step!
using OrderedCollections: OrderedDict
export OrderedDict
using Graphs: simplecycles, is_cyclic, DiGraph
using MetaGraphsNext: MetaGraph, add_vertex!, add_edge!

# Exports
export AbstractComponent, AbstractTimeDependentComponent, AbstractTimeIndependentComponent
export AbstractComponentIntegrator
export AbstractMermaidProblem, AbstractMermaidIntegrator, AbstractMermaidSolver, AbstractMermaidSolution
export AbstractConnectedVariable, AbstractConnector
export DEComponent, DuplicatedComponent, MOLComponent, AgentsComponent, SurrogateComponent, JumpComponent, TrixiParticlesComponent
export DEComponentIntegrator, DuplicatedComponentIntegrator, MOLComponentIntegrator, AgentsComponentIntegrator, SurrogateComponentIntegrator,
       JumpComponentIntegrator, TrixiParticlesComponentIntegrator
export TimeIndependentComponent
export Connector, ConnectedVariable, MermaidProblem, MermaidIntegrator
export ImplicitConnector
export AbstractMermaidSolver, MinimumTimeStepper
export MermaidSolution
export solve!, solve, init, step!
export getstate, setstate!, gettime, settime!
export name, timestep, variables
export fullname, runconnection, runconnection!
export systemdiagram

# Include src files
include("abstracts.jl")
include("connections.jl")
include("solutions.jl")
include("mermaidProblems.jl")
include("solvers.jl")
include("Duplicated.jl")
include("extensions.jl")
include("TimeIndependent.jl")
include("loops.jl")

# Documentation
"""
    setstate!(comp::AbstractComponentIntegrator, state)
    setstate!(comp::AbstractComponentIntegrator, key, value)

Set the state of a component.

# Arguments
- `comp::AbstractComponentIntegrator`: The component whose state is to be set.
- `state`: The new state to set for the entire component.
- `key`: The key specifying which part of the component's state to set.
- `value`: The value to set for the specified part of the component's state.
"""
function setstate! end

"""
    getstate(comp::AbstractComponentIntegrator; copy = false)
    getstate(comp::AbstractComponentIntegrator, key; copy = false)

Retrieve the state of a component.

# Arguments
- `comp::AbstractComponentIntegrator`: The component whose state is to be retrieved.
- `key`: The key specifying which part of the component's state to retrieve.

# Keyword Arguments
- `copy::Bool`: If `true`, a deep copy of the state is returned; otherwise, a reference to
    the state is returned (assuming the state is mutable).
"""
function getstate end

"""
    variables(comp::AbstractComponentIntegrator)
    variables(comp::AbstractComponent)

Retrieve the variable names of a component.

# Arguments
- `comp::Union{AbstractComponent, AbstractComponentIntegrator}`: The component (or component
    integrator) whose variable names are to be retrieved.

# Returns
- A collection of variable names (as strings) associated with the component. This includes
    all special variables such as `#time` and `#model` if applicable.
"""
function variables end

"""
    step!(int::AbstractComponentIntegrator)

Advance the state of the integrator `int` by one time step.

# Arguments
- `int::AbstractComponentIntegrator`: The integrator to advance.
"""
function step!(::AbstractComponentIntegrator) end

"""
    init(comp::AbstractComponent)

Initialises an integrator ([AbstractComponentIntegrator](@ref))
    for the given [AbstractComponent](@ref).

# Arguments
- `comp::AbstractComponent`: The component to be initialised.

# Returns
- `MermaidIntegrator`: The initialised integrator for the problem.
"""
function init(::AbstractComponent) end

"""
    systemdiagram(problem::MermaidProblem; detail=:ports, direction=:LR)

Create a system-topology diagram for a Mermaid problem.

This method is provided by an optional visualization extension. Loading Kroki.jl enables
the `MermaidProblem` method without adding rendering dependencies to Mermaid's core. The
extension returns a Graphviz-backed `Kroki.Diagram`.

The supported detail levels are `:components` and `:ports`; supported directions are `:LR`
and `:TB`. Creating the diagram is local and does not render it or contact a remote service.
"""
function systemdiagram(problem::AbstractMermaidProblem; kwargs...)
    throw(ArgumentError(
        "no systemdiagram method for $(typeof(problem)); loading Kroki.jl enables MermaidProblem diagrams"))
end

end
