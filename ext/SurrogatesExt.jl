module SurrogatesExt

using Mermaid
using Surrogates
using CommonSolve
using OrderedCollections: OrderedDict
# TODO time dependence: what if an ODE non-autonomous? want an option to include time in the surrogate?

"""
    SurrogateComponent(args...; kwargs...)

Represents a component that is replaced with a surrogate in the simulation, speeding up computation of a complex step! function.

# Arguments
- `component::AbstractTimeDependentComponent`: The original component to be replaced with a surrogate.
- `surrogate`: The surrogate model or method to use for the component.
- `lower_bound`: Lower bounds for each state variable for surrogate sampling.
- `upper_bound`: Upper bounds for each state variable for surrogate sampling.

# Keyword Arguments
- `name::AbstractString`: Name of the component. Defaults to the same as the original component.
- `timestep::Real`: Time step for the component. Defaults to the same as the original component.
- `model`: A Flux.jl model to use as the surrogate. If `nothing`, a default feedforward neural network is created.
- `state_names`: Dictionary mapping variable names (as strings) to their corresponding indices in the
    state vector or symbols from ModelingToolkit/Symbolics. Defaults to the same as the original component.
- `n_samples::Integer`: Number of samples to use for training the surrogate. Defaults to 1000.
- `n_epochs::Integer`: Number of training epochs for the surrogate. Defaults to 1000.
"""
function Mermaid.SurrogateComponent(
        component::AbstractTimeDependentComponent, surrogate, lower_bound, upper_bound;
        name::AbstractString = component.name, timestep::Real = component.timestep,
        state_names = component.state_names, n_samples::Integer = 1000, kwargs = ())
    return Mermaid.SurrogateComponent(
        component, name, surrogate, timestep, state_names, lower_bound,
        upper_bound, n_samples, kwargs)
end

function CommonSolve.init(c::SurrogateComponent)
    lower_bound = c.lower_bound
    upper_bound = c.upper_bound
    n_samples = c.n_samples
    integrator = CommonSolve.init(c.component)
    initial_state = getstate(integrator)
    function step(x)
        if x isa Tuple
            x = collect(x)
        end
        setstate!(integrator, x)
        CommonSolve.step!(integrator)
        return collect(getstate(integrator))
    end

    xys = sample(n_samples, lower_bound, upper_bound, SobolSample())
    zs = step.(xys)
    if length(lower_bound) == 1
        xys = [[x] for x in xys]
    end

    sgt = c.surrogate(xys, zs, lower_bound, upper_bound; c.kwargs...)

    return SurrogateComponentIntegrator(
        integrator, c, initial_state, 0.0, sgt)
end

function CommonSolve.step!(compInt::SurrogateComponentIntegrator)
    surr = compInt.surrogate(compInt.state)
    if length(surr) == 1
        compInt.state = surr[1]  # Convert 1-element array to scalar
    else
        compInt.state = vec(surr)
    end
    compInt.time += compInt.component.timestep
end

function Mermaid.getstate(compInt::SurrogateComponentIntegrator, key)
    if first(key.variable) == '#'
        if key.variable == "#time"
            return compInt.time
        end
    end
    setstate!(compInt.integrator, compInt.state)
    return getstate(compInt.integrator, key)
end

function Mermaid.getstate(compInt::SurrogateComponentIntegrator)
    return compInt.state
end

function Mermaid.setstate!(compInt::SurrogateComponentIntegrator, state)
    compInt.state = state
end

function Mermaid.setstate!(compInt::SurrogateComponentIntegrator,
        key::Mermaid.AbstractConnectedVariable, value)
    if first(key.variable) == '#'
        if key.variable == "#time"
            compInt.time = value
            return nothing
        end
    end
    setstate!(compInt.integrator, compInt.state)
    setstate!(compInt.integrator, key, value)
    compInt.state = getstate(compInt.integrator)
end

function Mermaid.variables(component::SurrogateComponent)
    return union(variables(component.component), ["#time"])
end

end
