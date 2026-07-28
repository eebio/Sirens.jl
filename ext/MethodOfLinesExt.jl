module MethodOfLinesExt

using Mermaid
using CommonSolve
using OrderedCollections: OrderedDict
using DiffEqBase

"""
    MOLComponent(model::DiffEqBase.AbstractDEProblem, alg::DiffEqBase.AbstractDEAlgorithm;
                 name::String="MOL", timestep::Real=1.0, intkwargs::Tuple=(),
                 state_names::Dict{String,Any}=Dict{String,Any}())

A Mermaid component that wraps a Method of Lines discretized PDE as a SciML
    DifferentialEquations problem.

# Arguments
- `model::DiffEqBase.AbstractDEProblem`: The SciML Differential Equations problem (e.g.,
    ODEProblem, etc.) from MethodOfLines discretization.
- `alg::DiffEqBase.AbstractDEAlgorithm`: Algorithm from DifferentialEquations.jl to be used
    for solving the DEProblem.

# Keyword Arguments
- `name::AbstractString`: Name of the component. Defaults to "MOL".
- `timestep::Real`: Time step for the component. Defaults to 1.0.
- `intkwargs`: Additional keyword arguments for the DE solver. Defaults to no keywords.
- `state_names`: Dictionary mapping variable names (as strings) to their corresponding
    indices in the state vector or symbols from Symbolics.jl. Defaults to an empty
    dictionary. For PDEs with spatial discretization, map logical variable names
    (e.g., \"concentration\") to state vector indices or ranges.

# Special Variables
- `#time`: The current time (`integrator.t`).
- `#state`: The full discretized state vector (`integrator.u`).
- `#integrator`: The underlying DifferentialEquations.jl integrator object.

# Notes
MOLComponent is useful for connecting discretized PDEs to other models. When mapping
between different spatial grids or resolutions (e.g., PDE grid to agent positions),
use a connector function to perform interpolation or other spatial transformations.
"""
function Mermaid.MOLComponent(model::DiffEqBase.AbstractDEProblem,
        alg::DiffEqBase.AbstractDEAlgorithm; name = "MOL",
        timestep::Real = 1.0, intkwargs = (), state_names = Dict{String, Any}())
    return Mermaid.MOLComponent(model, name, state_names, timestep, alg, intkwargs)
end

function CommonSolve.init(c::MOLComponent)
    integrator = MOLComponentIntegrator(
        init(c.model, c.alg; dt = c.timestep, c.intkwargs...), c)
    return integrator
end

function CommonSolve.step!(compInt::MOLComponentIntegrator)
    CommonSolve.step!(compInt.integrator, timestep(compInt), true)
end

function Mermaid.getstate(compInt::MOLComponentIntegrator, key)
    if first(key.variable) == '#'
        if key.variable == "#time"
            return compInt.integrator.t
        elseif key.variable == "#integrator"
            return compInt.integrator
        elseif key.variable == "#state"
            return compInt.integrator.u
        end
    end
    if isnothing(key.variableindex)
        # No index for variable
        index = compInt.component.state_names[key.variable]
        return compInt.integrator[index]
    else
        index = compInt.component.state_names[key.variable]
        return compInt.integrator[index][key.variableindex]
    end
end

function Mermaid.getstate(compInt::MOLComponentIntegrator)
    # Return the full state vector
    return compInt.integrator.u
end

function Mermaid.setstate!(compInt::MOLComponentIntegrator, key, value)
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
    if isnothing(key.variableindex)
        # No index for variable
        index = compInt.component.state_names[key.variable]
        compInt.integrator[index] = value
    else
        key.variableindex isa AbstractVector
        # Single index for one variable
        index = compInt.component.state_names[key.variable]
        if length(index[key.variableindex]) == 1
            # If the index is a single value, set it directly
            compInt.integrator.u[(index)[key.variableindex][1]] = value
        else
            # If the index is a vector, set the corresponding values
            compInt.integrator.u[(index)[key.variableindex]] .= value
        end
    end
end

function Mermaid.setstate!(compInt::MOLComponentIntegrator, value)
    # Set the full state vector
    compInt.integrator.u = value
end

function Mermaid.variables(component::MOLComponent)
    return union(keys(component.state_names), ["#time", "#integrator", "#state"])
end

end
