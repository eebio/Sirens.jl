module DiffEqExt

using Sirens
using CommonSolve
using DiffEqBase
using OrderedCollections: OrderedDict

"""
    DEComponent(model::DiffEqBase.AbstractDEProblem, alg;
                name::String="DE", timestep::Float64=1.0, intkwargs::NamedTuple=(;),
                state_names::Dict{String,Any}=Dict{String,Any}())
    DEComponent(model::DiffEqBase.AbstractDEProblem; kwargs...)

A Sirens component that wraps a SciML Differential Equations problem (ODEProblem,
    DAEProblem, etc).

# Arguments
- `model::DiffEqBase.AbstractDEProblem`: The SciML Differential Equations problem (e.g.,
    ODEProblem, etc.)
- `alg`: Algorithm from DifferentialEquations.jl to be used
    for solving the DEProblem. If no algorithm is provided, the algorithm will be
    automatically chosen by DifferentialEquations.jl.

# Keyword Arguments
- `name::AbstractString`: Name of the component. Defaults to "DE".
- `timestep::Real`: Time step for the component. Defaults to 1.0.
- `intkwargs`: Additional keyword arguments for the DE solver. Defaults to no keywords.
- `state_names`: Dictionary mapping variable names (as strings) to their corresponding
    indices in the state vector or symbols from Symbolics.jl. Defaults to an empty
    dictionary. Map strings like \"x\" to indices (1, 2, ...) or symbolic variables.

# Special Variables
- `#time`: The current time (`integrator.t`).
- `#state`: The full state vector (`integrator.u`).
- `#integrator`: The underlying DifferentialEquations.jl integrator object.

# Examples
```julia
function f!(du, u, p, t)
    du[1] = -u[1]
end
prob = ODEProblem(f!, [1.0], (0.0, 10.0))
comp = DEComponent(prob, Tsit5(); name=\"ode_comp\",
                   state_names=Dict(\"x\" => 1))
```
"""
function Sirens.DEComponent(model::DiffEqBase.AbstractDEProblem,
        alg; name = "DE", timestep::Real = 1.0, intkwargs = (;),
        state_names = Dict{String, Any}())
    return Sirens.DEComponent(model, name, state_names, timestep, alg, intkwargs)
end

function Sirens.DEComponent(model::DiffEqBase.AbstractDEProblem; kwargs...)
    return Sirens.DEComponent(model, nothing; kwargs...)
end

function CommonSolve.init(c::Sirens.DEComponent)
    if isnothing(c.alg)
        integrator = init(c.model; c.intkwargs...)
        return Sirens.DEComponentIntegrator(integrator, c)
    else
        integrator = init(c.model, c.alg; c.intkwargs...)
        return Sirens.DEComponentIntegrator(integrator, c)
    end
end

function CommonSolve.step!(compInt::Sirens.DEComponentIntegrator)
    CommonSolve.step!(compInt.integrator, timestep(compInt), true)
end

function Sirens.getstate(compInt::Sirens.DEComponentIntegrator, key)
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

function Sirens.getstate(compInt::Sirens.DEComponentIntegrator)
    return compInt.integrator.u
end

function Sirens.setstate!(compInt::Sirens.DEComponentIntegrator, key, value)
    derivative_discontinuity!(compInt.integrator, true)
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

function Sirens.setstate!(compInt::Sirens.DEComponentIntegrator, value)
    derivative_discontinuity!(compInt.integrator, true)
    compInt.integrator.u = value
end

function Sirens.variables(component::Sirens.DEComponent)
    return union(keys(component.state_names), ["#time", "#integrator", "#state"])
end

end
