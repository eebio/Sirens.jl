module TrixiParticlesExt

using Mermaid
using CommonSolve
using TrixiParticles
using DiffEqBase
using OrderedCollections: OrderedDict

"""
    TrixiParticlesComponent(semi::TrixiParticles.Semidiscretization, alg;
                name::String="TrixiParticles", timestep::Float64=1.0,
                intkwargs::Tuple=(), tspan=(0.0, Inf),
                state_names::Dict{String,Any}=Dict{String,Any}())

A Mermaid component that wraps a TrixiParticles.jl particle method simulation.

# Arguments
- `semi::TrixiParticles.Semidiscretization`: TrixiParticles semidiscretization object.
- `alg`: Algorithm from DifferentialEquations.jl or TrixiParticles.jl to solve the
    DynamicalODEProblem.

# Keyword Arguments
- `name::AbstractString`: Name of the component. Defaults to "TrixiParticles".
- `timestep::Real`: Time step for the component. Defaults to 1.0.
- `intkwargs`: Additional keyword arguments for the DE solver. Defaults to no keywords.
- `tspan`: Time span for the simulation. Defaults to (0.0, Inf).
- `state_names`: Dictionary mapping variable names (as strings) to their corresponding
    indices in the state vector or symbols from Symbolics.jl. Defaults to an empty
    dictionary. Typically maps particle positions, velocities, or properties.

# Special Variables
- `#time`: The current time (`integrator.t`).
- `#state`: The full particle state vector (`integrator.u`).
- `#integrator`: The underlying DifferentialEquations.jl integrator object.
- `#semi`: The TrixiParticles semidiscretization object (read-only; cannot be used with `setstate!`).
"""
function Mermaid.TrixiParticlesComponent(semi::TrixiParticles.Semidiscretization,
        alg; name = "TrixiParticles", timestep::Real = 1.0, intkwargs = (),
        tspan = (0.0, Inf), state_names = Dict{String, Any}())
    ode = semidiscretize(semi, tspan)
    return Mermaid.TrixiParticlesComponent(
        ode, semi, name, state_names, timestep, alg, intkwargs)
end

function CommonSolve.init(c::Mermaid.TrixiParticlesComponent)
    integrator = Mermaid.TrixiParticlesComponentIntegrator(
        init(c.model, c.alg; c.intkwargs...), c)
    return integrator
end

function CommonSolve.step!(compInt::Mermaid.TrixiParticlesComponentIntegrator)
    CommonSolve.step!(compInt.integrator, timestep(compInt), true)
end

function Mermaid.getstate(compInt::Mermaid.TrixiParticlesComponentIntegrator, key)
    if first(key.variable) == '#'
        if key.variable == "#time"
            return compInt.integrator.t
        elseif key.variable == "#semi"
            return compInt.component.semi
        elseif key.variable == "#state"
            return getstate(compInt)
        elseif key.variable == "#integrator"
            return compInt.integrator
        end
    end
    index = compInt.component.state_names[key.variable]
    return compInt.integrator[index]
end

function Mermaid.getstate(compInt::Mermaid.TrixiParticlesComponentIntegrator)
    return compInt.integrator.u
end

function Mermaid.setstate!(compInt::Mermaid.TrixiParticlesComponentIntegrator, key, value)
    derivative_discontinuity!(compInt.integrator, true)
    if first(key.variable) == '#'
        if key.variable == "#time"
            derivative_discontinuity!(compInt.integrator, true)
            compInt.integrator.t = value
            return nothing
        elseif key.variable == "#integrator"
            compInt.integrator = value
            return nothing
        elseif key.variable == "#state"
            setstate!(compInt, value)
            return nothing
        end
    end
    index = compInt.component.state_names[key.variable]
    compInt.integrator[index] = value
end

function Mermaid.setstate!(compInt::Mermaid.TrixiParticlesComponentIntegrator, value)
    derivative_discontinuity!(compInt.integrator, true)
    compInt.integrator.u = value
end

function Mermaid.variables(component::Mermaid.TrixiParticlesComponent)
    return union(keys(component.state_names), ["#semi", "#time", "#state", "#integrator"])
end

end
