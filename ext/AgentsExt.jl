module AgentsExt

using Mermaid
using CommonSolve
using Agents
using OrderedCollections: OrderedDict

export AgentsComponent

"""
    AgentsComponent(model::StandardABM; name="Agents Component",
                    state_names=Dict{String,Any}(), timestep::Real=1.0)

A Mermaid component that wraps an agent-based model (ABM) using the Agents.jl package.

# Arguments
- `model::StandardABM`: The agent-based model to be solved.

# Keyword Arguments
- `name::AbstractString`: The name of the component. Defaults to "Agents".
- `state_names`: A dictionary mapping variable names (as strings) to their corresponding
    properties (agent properties or model properties) in the `model`. Defaults to an empty
    dictionary. Values can be agent properties (accessed per agent) or model properties.
- `timestep::Real=1`: The time step for the component (not the ABM solver timestep), i.e.
    how frequently should the inputs and outputs be updated (in units of `abmtime(model)`).
    For example, if `timestep=5`, the component will step the ABM 5 times for every
    synchronization, and set #time=5.

# Special Variables
- `#time`: The component clock (independent from `abmtime(model)`).
- `#model`: The current `StandardABM` object (read-only; use `getstate` with `copy=true` to
    get a copy).
- `#ids`: The vector of all current agent IDs (read-only; cannot be used with `setstate!`).

# state_names Semantics
- A key without a variable index accesses agent properties for all agents or model
    properties.
- A key with a variable index (e.g., `\"comp.var[1:5]\"\") accesses specific agent IDs.
- Since the `variableindex` is used for accessing the properties of particular agents, use a
    connector function to index into complex properties.

# Examples
```julia
comp = AgentsComponent(model;
    name=\"abm_comp\",
    state_names=Dict(\"x\" => :pos_x, \"y\" => :pos_y))
```
"""
function Mermaid.AgentsComponent(model::StandardABM;
        name::AbstractString = "Agents", state_names = Dict{String, Any}(),
        timestep::Real = 1)
    return Mermaid.AgentsComponent(model, name, state_names, timestep)
end

function CommonSolve.init(c::AgentsComponent)
    integrator = AgentsComponentIntegrator(deepcopy(c.model), 0.0, c)
    return integrator
end

function CommonSolve.step!(compInt::AgentsComponentIntegrator)
    step!(compInt.integrator, timestep(compInt))
    compInt.time += timestep(compInt)
end

function Mermaid.getstate(compInt::AgentsComponentIntegrator, key::ConnectedVariable)
    if first(key.variable) == '#'
        # Special variables
        if key.variable == "#time"
            return compInt.time
        end
        if key.variable == "#model"
            return getstate(compInt)
        end
        if key.variable == "#ids"
            return collect(allids(compInt.integrator))
        end
    end
    index = compInt.component.state_names[key.variable]
    if isnothing(key.variableindex)
        props = abmproperties(compInt.integrator)
        if !isnothing(props)
            # Check model properties
            if props isa Dict
                if haskey(props, index)
                    return props[index]
                end
            else
                # Assume props is a struct
                if hasproperty(props, index)
                    return getproperty(compInt.integrator, index)
                end
            end
        end
        # Otherwise, assume it's an agent property and return it for all agents
        return [getproperty(i, index) for i in allagents(compInt.integrator)]
    else
        props = abmproperties(compInt.integrator)
        if !isnothing(props)
            # Check model properties
            if props isa Dict
                if haskey(props, index)
                    return props[index][key.variableindex]
                end
            else
                # Assume props is a struct
                if hasproperty(props, index)
                    return getproperty(compInt.integrator, index)[key.variableindex]
                end
            end
        end
        # Otherwise, assume it's an agent property and return it for all agents in range
        out = [getproperty(compInt.integrator[i], index) for i in key.variableindex]
        if length(out) == 1
            return out[1] # If only one agent, return the single value
        else
            return out # Otherwise, return the vector of values
        end
    end
end

function Mermaid.setstate!(
        compInt::AgentsComponentIntegrator, key::ConnectedVariable, value)
    # TODO add ids exception? Is there a way to specify the id when creating an agent
    if first(key.variable) == '#'
        # Special variables
        if key.variable == "#time"
            compInt.time = value
            return nothing
        end
        if key.variable == "#model"
            setstate!(compInt, value)
            return nothing
        end
    end
    index = compInt.component.state_names[key.variable]
    if isnothing(key.variableindex)
        props = abmproperties(compInt.integrator)
        if !isnothing(props)
            # Check model properties
            if props isa Dict
                if haskey(props, index)
                    return props[index] = value
                end
            else
                # Assume props is a struct
                if hasproperty(props, index)
                    return setproperty!(compInt.integrator, index, value)
                end
            end
        end
        # Otherwise, assume it's an agent property and set it for all agents
        for (i, agent) in enumerate(allagents(compInt.integrator))
            setproperty!(agent, index, value[i])
        end
    else
        props = abmproperties(compInt.integrator)
        if !isnothing(props)
            # Check model properties
            if props isa Dict
                if haskey(props, index)
                    k = 1
                    for i in key.variableindex
                        props[index][i] = value[k]
                        k += 1
                    end
                    return nothing
                end
            else
                # Assume props is a struct
                if hasproperty(props, index)
                    k = 1
                    for i in key.variableindex
                        getproperty(compInt.integrator, index)[i] = value[k]
                        k += 1
                    end
                    return nothing
                end
            end
        end
        # Otherwise, assume it's an agent property and set it for all agents in range
        k = 1
        for i in key.variableindex
            setproperty!(compInt.integrator[i], index, value[k])
            k += 1
        end
    end
    return nothing
end

function Mermaid.getstate(compInt::AgentsComponentIntegrator)
    return compInt.integrator
end

function Mermaid.setstate!(compInt::AgentsComponentIntegrator, state::StandardABM)
    compInt.integrator = state
end

function Mermaid.variables(component::AgentsComponent)
    return union(keys(component.state_names), ["#model", "#time", "#ids"])
end
end
