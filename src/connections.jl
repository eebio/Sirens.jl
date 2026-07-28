"""
    ConnectedVariable <: AbstractConnectedVariable

Points to a variable within a component.

# Fields
- `component::String`: Name of the component.
- `variable::String`: Name of the variable.
- `variableindex::Union{Nothing,Vector{Int},Int}`: Index or range for the variable,
    if applicable.
- `duplicatedindex::Union{Nothing,Vector{Int},Int}`: Index for duplicated
    components, if applicable.
"""
struct ConnectedVariable{U <: AbstractString, V <: AbstractString, X <: Union{Nothing, AbstractVector{Int}, Int}, Y <: Union{Nothing, AbstractVector{Int}, Int}} <: AbstractConnectedVariable
    component::U
    variable::V
    variableindex::X
    duplicatedindex::Y
end

function Base.hash(cv::ConnectedVariable, h::UInt) return hash(fullname(cv), h) end
function Base.isequal(cv1::ConnectedVariable, cv2::ConnectedVariable)
    return fullname(cv1) == fullname(cv2)
end

"""
    ConnectedVariable(name::AbstractString)

Construct a [ConnectedVariable](@ref) from its canonical fullname.

# Arguments
- `name::AbstractString`: The full variable name.

# Syntax and Examples

Connected variables are specified as strings in one of these forms:

| Syntax | Meaning |
| --- | --- |
| `component.variable` | A variable in a component |
| `component.variable[i]` | An index into a variable |
| `component[j].variable` | Instance `j` of a duplicated component |
| `component[j].variable[i]` | Both kinds of indexing |

# Examples
- `ConnectedVariable("comp.var")`: Variable `var` in component `comp`.
- `ConnectedVariable("comp.var[1:5]")`: Variable indices 1 through 5 (variable index).
- `ConnectedVariable("comp[2].var")`: Variable `var` from duplicated instance 2 (duplicated
    index).
- `ConnectedVariable("comp[1:3].var[4]")`: Variable index 4 from duplicated instances 1-3.

# Parsing
Indices are parsed as Julia expressions, so use literal integer indices and ranges:
- `1` for a single index.
- `1:5` for a range.
- `[1, 3]` for a vector of indices.
"""
function ConnectedVariable(name::AbstractString)
    # Parse the variable name to extract its parts
    component, variable = split(name, ".")
    # Is there a variable index
    if contains(variable, "[")
        variable, index = split(variable, "[")
        # Strip the final "]"
        index = strip(index, ']')
        # This will parse "1:5" to a UnitRange{Int} or "3" to an Int
        index = eval(Meta.parse(index))
    else
        # No index
        index = nothing
    end
    # Is there a duplicated index
    if contains(component, "[")
        component, dupindex = split(component, "[")
        # Strip the final "]"
        dupindex = strip(dupindex, ']')
        # This will parse "1:5" to a UnitRange{Int} or "3" to an Int
        dupindex = eval(Meta.parse(dupindex))
    else
        dupindex = nothing
    end
    return ConnectedVariable(component, variable, index, dupindex)
end

"""
    Connector <: AbstractConnector

Represents a connection between multiple [ConnectedVariables](@ref ConnectedVariable),
possibly with a transformation function.

# Fields
- `inputs::Vector{<:AbstractConnectedVariable}`: Input variables for the connector.
- `outputs::Vector{<:AbstractConnectedVariable}`: Output variables for the connector.
- `func::Union{Nothing,Function}`: Optional function to transform inputs to outputs.
"""
struct Connector <: AbstractConnector
    inputs::Vector{ConnectedVariable}
    outputs::Vector{ConnectedVariable}
    func::Union{Nothing, Function}
end

"""
    Connector(inputs, outputs; func=nothing)

Construct a [Connector](@ref) from string names for inputs and outputs.

# Arguments
- `inputs::Vector{<:AbstractString}`: Names of input variables.
- `outputs::Vector{<:AbstractString}`: Names of output variables.

# Keyword Arguments
- `func`: Optional transformation function. Defaults to `nothing` (identity for single
    input).

# Connector Semantics

# Input and Output Handling
- Inputs are read in the order given by `inputs`.
- With `func=nothing` and a single input, the input is passed unchanged to every output.
- With `func=nothing` and multiple inputs, input values are collected into a vector.
- With a function, Mermaid calls `func(input1, input2, ...)` using positional arguments.
  The function receives input values in order, not a vector.
- Output values (from `func` or the single input) are set to every output in order.

# Connection Timing and Application
A connector is only applied is the time of all inputs is earlier than the time of all
    outputs.

Connectors are applied before component steps.
A connector does not automatically run again after a component step; it must become eligible
at a subsequent event.

# Mapping and Transformations
The function (`func`) receives positional arguments for each input and must return
a value compatible with every output:
- Mermaid performs no automatic unit conversion, interpolation, broadcasting, or reshaping.
- Spatial mapping between grids, coordinate systems, or resolutions must be explicit in
    `func`.
- For no-output connectors (side effects), the return value is ignored.

# Variable and Duplicated Indices
Variable indices (e.g., `[1:5]`) and duplicated indices (e.g., `[2]` in `comp[2].var`)
are passed to component `getstate`/`setstate!` implementations:
- For a duplicated component, duplicated index selects instances; variable index selects
  parts of each instance's state. Both may be used together.
- The exact shape of returned values depends on the component's indexing implementation.

See also [MinimumTimeStepper](@ref).
"""
function Connector(; inputs::Vector{T}, outputs::Vector{S},
        func = nothing) where {T <: AbstractString} where {S <: AbstractString}
    inputs = [ConnectedVariable(i) for i in inputs]
    outputs = [ConnectedVariable(o) for o in outputs]
    return Connector(inputs, outputs, func)
end

"""
    fullname(var::AbstractConnectedVariable)

Return the full name of a [ConnectedVariable](@ref) as a string.

# Arguments
- `var::AbstractConnectedVariable`: The connected variable to get the full name for.

# Returns
- `String`: The full name of the connected variable.
"""
function Base.fullname(var::AbstractConnectedVariable)
    # Construct the full name of the variable
    comp = var.component
    dupindex = isnothing(var.duplicatedindex) ? "" : "[" * string(var.duplicatedindex) * "]"
    variable = var.variable
    index = isnothing(var.variableindex) ? "" : "[" * string(var.variableindex) * "]"
    return comp * dupindex * "." * variable * index
end

"""
    runconnection(merInt::AbstractMermaidIntegrator, conn::AbstractConnector)

Extract all the input states from `merInt`, apply the connection function, and return the
output.

# Arguments
- `merInt::AbstractMermaidIntegrator`: The Mermaid integrator containing the components.
- `conn::AbstractConnector`: The connector defining the connection.
"""
function runconnection(merInt::AbstractMermaidIntegrator, conn::AbstractConnector)
    # Get the values of the connectors inputs
    inputs = []
    for input in conn.inputs
        # Find the corresponding integrator
        index = findfirst(
            i -> name(i) == input.component, merInt.integrators)
        if index !== nothing
            integrator = merInt.integrators[index]
            # Get the value of the input from the integrator
            push!(inputs, getstate(integrator, input))
        end
    end
    if isnothing(conn.func)
        if length(inputs) == 1
            outputs = inputs[1]
        else
            outputs = inputs
        end
    else
        outputs = conn.func(inputs...)
    end
    return outputs
end

"""
    runconnection!(merInt::AbstractMermaidIntegrator, conn::AbstractConnector)

Extract all input states from `merInt`, apply the connection function, and set output
states in `merInt`.

# Arguments
- `merInt::AbstractMermaidIntegrator`: The Mermaid integrator containing components.
- `conn::AbstractConnector`: The connector defining inputs, outputs, and transformation.

# Behavior
1. Calls `runconnection` to compute outputs.
2. Sets each output value in the corresponding component via `setstate!`.
3. Outputs are set in order; later outputs can depend on earlier ones if they share state.
"""
function runconnection!(merInt::AbstractMermaidIntegrator, conn::AbstractConnector)
    outputs = runconnection(merInt, conn)
    # Set the outputs in the corresponding integrators
    for output in conn.outputs
        # Find the corresponding integrator
        index = findfirst(
            i -> name(i) == output.component, merInt.integrators)
        if index !== nothing
            integrator = merInt.integrators[index]
            # Set the input value for the integrator
            setstate!(integrator, output, outputs)
        end
    end
end

function checkconnection(conn::AbstractConnector, merInt::AbstractMermaidIntegrator)
    # Check if all inputs are earlier in time than (or equal to) the time of all outputs
    max_input_time = -Inf
    for input in conn.inputs
        conn_tmp = ConnectedVariable(input.component, "#time", nothing, nothing)
        time_tmp = prevfloat(getstate(merInt, conn_tmp))
        # Apply timescales
        time_tmp *= prevfloat(merInt.timescales[findfirst(i -> name(i) == input.component, merInt.integrators)])
        if time_tmp > max_input_time
            max_input_time = time_tmp
        end
    end
    min_output_time = Inf
    for output in conn.outputs
        conn_tmp = ConnectedVariable(output.component, "#time", nothing, nothing)
        time_tmp = nextfloat(getstate(merInt, conn_tmp))
        # Apply timescales
        time_tmp *= nextfloat(merInt.timescales[findfirst(i -> name(i) == output.component, merInt.integrators)])
        if time_tmp < min_output_time
            min_output_time = time_tmp
        end
    end
    return max_input_time <= min_output_time
end
