module JumpProcessesExt

using Mermaid
using CommonSolve
using DiffEqBase
using JumpProcesses
using OrderedCollections: OrderedDict

"""
    JumpComponent(model::JumpProblem, alg;
                name::String="Jump", timestep::Float64=1.0, intkwargs::Tuple=(),
                state_names::Dict{String,Any}=Dict{String,Any}())

A Mermaid component that wraps a JumpProcesses.jl jump process problem.

# Arguments
- `model::JumpProblem`: SciML Jump problem containing a continuous ODE and jump events.
- `alg`: Algorithm from DifferentialEquations.jl to be used for solving the JumpProblem.

# Keyword Arguments
- `name::AbstractString`: Name of the component. Defaults to "Jump".
- `timestep::Real`: Time step for the component. Defaults to 1.0.
- `intkwargs`: Additional keyword arguments for the Jump solver. Defaults to no keywords.
- `state_names`: Dictionary mapping variable names (as strings) to their corresponding
    indices in the state vector or symbols from Symbolics.jl. Defaults to an empty
    dictionary.

# Special Variables
- `#time`: The current time (`integrator.t`).
- `#state`: The full state vector (`integrator.u`).
- `#integrator`: The underlying DifferentialEquations.jl integrator object.
"""
function Mermaid.JumpComponent(model::JumpProblem,
        alg; name = "Jump", timestep::Real = 1.0, intkwargs = (),
        state_names = Dict{String, Any}())
    return Mermaid.JumpComponent(model, name, state_names, timestep, alg, intkwargs)
end

function CommonSolve.init(c::Mermaid.JumpComponent)
    integrator = Mermaid.JumpComponentIntegrator(
        init(c.model, c.alg; c.intkwargs...), c)
    return integrator
end

function CommonSolve.step!(compInt::Mermaid.JumpComponentIntegrator)
    # Doing reset here rather than setstate! ensures we only reset at the last possible time
    if compInt.integrator.derivative_discontinuity
        reset_aggregated_jumps!(compInt.integrator)
    end
    CommonSolve.step!(compInt.integrator, timestep(compInt), true)
end

function Mermaid.getstate(compInt::Mermaid.JumpComponentIntegrator, key)
    if first(key.variable) == '#'
        if key.variable == "#time"
            return compInt.integrator.t
        elseif key.variable == "#integrator"
            return compInt.integrator
        elseif key.variable == "#state"
            return compInt.integrator.u
        end
    end
    index = compInt.component.state_names[key.variable]
    return compInt.integrator[index]
end

function Mermaid.getstate(compInt::Mermaid.JumpComponentIntegrator)
    return compInt.integrator.u
end

function Mermaid.setstate!(compInt::Mermaid.JumpComponentIntegrator, key, value)
    derivative_discontinuity!(compInt.integrator, true)
    # Clear jump caches too
    if first(key.variable) == '#'
        if key.variable == "#time"
            compInt.integrator.t = value
            return nothing
        elseif key.variable == "#integrator"
            compInt.integrator = value
            return nothing
        elseif key.variable == "#state"
            compInt.integrator.u = value
            return nothing
        end
    end
    index = compInt.component.state_names[key.variable]
    compInt.integrator[index] = value
end

function Mermaid.setstate!(compInt::Mermaid.JumpComponentIntegrator, value)
    derivative_discontinuity!(compInt.integrator, true)
    compInt.integrator.u = value
end

function Mermaid.variables(component::Mermaid.JumpComponent)
    return union(keys(component.state_names), ["#time", "#integrator", "#state"])
end

end
