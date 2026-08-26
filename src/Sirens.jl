module Sirens
@doc read(joinpath(dirname(@__DIR__), "README.md"), String) Sirens

# Imports, Usings and Reexports
import CommonSolve: solve!, solve, init, step!
using OrderedCollections: OrderedDict
export OrderedDict
using Graphs: simplecycles, is_cyclic, DiGraph
using MetaGraphsNext: MetaGraph, add_vertex!, add_edge!
using AutoHashEquals

# Exports
export AbstractComponent, AbstractTimeDependentComponent, AbstractTimeIndependentComponent
export AbstractComponentIntegrator
export AbstractSirenProblem, AbstractSirenIntegrator, AbstractSirenSolver, AbstractSirenSolution
export AbstractConnectedVariable, AbstractConnector
export DEComponent, DuplicatedComponent, MOLComponent, AgentsComponent, SurrogateComponent, JumpComponent, TrixiParticlesComponent
export DEComponentIntegrator, DuplicatedComponentIntegrator, MOLComponentIntegrator, AgentsComponentIntegrator, SurrogateComponentIntegrator,
       JumpComponentIntegrator, TrixiParticlesComponentIntegrator
export TimeIndependentComponent
export Connector, ConnectedVariable, SirenProblem, SirenIntegrator
export ImplicitConnector
export AbstractSirenSolver, MinimumTimeStepper
export SirenSolution
export solve!, solve, init, step!
export getstate, setstate!, gettime, settime!
export name, timestep, variables
export fullname, runconnection, runconnection!
export systemdiagram

# Include src files
include("abstracts.jl")
include("connections.jl")
include("solutions.jl")
include("sirenProblems.jl")
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
- `SirenIntegrator`: The initialised integrator for the problem.
"""
function init(::AbstractComponent) end

"""
    systemdiagram(problem::AbstractSirenProblem; detail=:ports, direction=:LR)

Create a system-topology diagram for a Siren problem. Requires loading a supported graphical
    backend such as Kroki.jl.

# Arguments
- `problem::AbstractSirenProblem`: The Siren problem for which to create a diagram.

# Keyword Arguments
- `detail::Symbol`: Detail level for the diagram. Defaults to :ports (connections between
    variables). Other options include :components (connections between components, ignoring
    specific variables).
- `direction::Symbol`: Direction of the diagram. Defaults to :LR (left to right). Other
    options include :TB (top to bottom).
"""
function systemdiagram(problem::AbstractSirenProblem; kwargs...)
    error("no systemdiagram method for $(typeof(problem)); loading Kroki.jl enables SirenProblem diagrams")
end

end
