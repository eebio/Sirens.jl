struct SirenSolutionData{K<:Tuple,V<:Tuple} <: AbstractDict{AbstractConnectedVariable,Any}
    keys::K
    values::V
end

"""
    SirenSolution{X, Y<:SirenSolutionData} <: AbstractSirenSolution

Stores the solution of a [SirenProblem](@ref) over time.

# Fields
- `t::X`: Time points at which the solution is saved.
- `u::Y<:SirenSolutionData`: A dictionary-like structure storing the saved states for each
    variable in the problem.

# Interpolation

A solution can be interpolated at arbitrary times using callable syntax:

```julia
(sol::AbstractSirenSolution)(t::Real)
```

This returns a new `SirenSolution` with interpolated states at time `t`.

**Interpolation Rules:**
- For numeric states and numeric arrays: Uses linear interpolation between saved time points.
- For non-numeric states (e.g., Agents.jl models, objects): Uses constant interpolation
    (returns the state from the last saved time point before or at `t`).

The time `t` must be within `[sol.t[1], sol.t[end]]`, otherwise a `BoundsError` is thrown.

# Examples

```julia
sol(2.5)  # Interpolate solution at time t=2.5
```
"""
struct SirenSolution{X,Y<:SirenSolutionData} <: AbstractSirenSolution
    t::X
    u::Y
end

"""
    SirenSolution(int::SirenIntegrator) <: AbstractSirenSolution

Create a [SirenSolution](@ref) object initialized for the `save_vars`/variables in the
    given SirenIntegrator.

# Arguments
- `int::SirenIntegrator`: The integrator to extract solution structure from.

# Returns
- `SirenSolution`: A new [SirenSolution](@ref) object with empty time and state arrays
    for each variable to be saved.
"""
function SirenSolution(int::AbstractSirenIntegrator)
    u = SirenSolutionData(int)
    return SirenSolution(Vector{typeof(int.currtime)}(), u)
end

"""
    update_solution!(sol::SirenSolution, sirenInt::SirenIntegrator)

Update the [SirenSolution](@ref) `sol` with the current time and state from the
    SirenIntegrator.

# Arguments
- `sol::SirenSolution`: The [SirenSolution](@ref) to be updated.
- `sirenInt::SirenIntegrator`: The integrator object providing the current time (`currtime`)
    and states to access via `getstate`.
"""
function update_solution!(sol::AbstractSirenSolution, sirenInt::AbstractSirenIntegrator)
    push!(sol.t, sirenInt.currtime)
    _push_states!(sol.u.values, sol.u.keys, sirenInt)
    return sol
end

@inline _push_states!(::Tuple{}, ::Tuple{}, sirenInt) = nothing
@inline function _push_states!(values::Tuple, keys::Tuple, sirenInt)
    push!(first(values), getstate(sirenInt, first(keys); copy=true))
    _push_states!(Base.tail(values), Base.tail(keys), sirenInt)
    return nothing
end

"""
    Base.getindex(sol::AbstractSirenSolution, var::AbstractString)
    Base.getindex(sol::AbstractSirenSolution, var::AbstractConnectedVariable)
    Base.getindex(sol::AbstractSirenSolution, index::Int)

Get the solution for a variable `var` or at a time index `index` from a
    [SirenSolution](@ref).

# Arguments
- `sol::AbstractSirenSolution`: The solution object.
- `var::Union{AbstractString, AbstractConnectedVariable}`: The variable name, optionally
    with indices like `\"comp.var[1:3]\"` or `\"comp[2].var[4]\"`.
- `index::Int`: The time index (1-based) into the saved times.

# Returns
- If `var` is provided, returns a vector of saved states for that variable across all times.
- If `index` is provided, returns a new [SirenSolution](@ref) containing only the data
    at that time index for each variable.

# Examples
```julia
sol[\"comp.var\"]        # All saved states for variable \"comp.var\"
sol[ConnectedVariable(\"comp[1].var\")]  # States for duplicated instance 1
sol[3]                 # Solution data at the 3rd saved time point
```
"""
function Base.getindex(sol::AbstractSirenSolution, var::AbstractString)
    var = ConnectedVariable(var)
    return Base.getindex(sol, var)
end

function Base.getindex(sol::AbstractSirenSolution, var::AbstractConnectedVariable)
    if haskey(sol.u, var)
        return sol.u[var]
    else
        # See if we have a key without an index
        # TODO I'm not sure how the duplicatedindex data is stored in the solution
        var_no_index = ConnectedVariable(var.component, var.variable, nothing, nothing)
        if haskey(sol.u, var_no_index)
            return [i[var.variableindex] for i in sol.u[var_no_index]]
        end
        for key in keys(sol.u)
            if !isnothing(key.variableindex) && !isnothing(var.variableindex)
                if key.variable == var.variable && key.component == var.component &&
                   issubset(var.variableindex, key.variableindex)
                    if length(var.variableindex) == 1
                        # If the variableindex is a single value, return at that index
                        return [i[findfirst(
                            x -> x == var.variableindex[1], key.variableindex)]
                                for i in sol.u[key]]
                    else
                        return [[i[findfirst(x -> x == v, key.variableindex)]
                                 for v in var.variableindex] for i in sol.u[key]]
                    end
                end
            end
        end
    end
    throw(KeyError(var))
end

function Base.getindex(sol::AbstractSirenSolution, index::Integer)
    if index < 1 || index > length(sol.t)
        throw(BoundsError(sol.t, index))
    end
    data = SirenSolutionData(sol.u.keys, map(v -> v[index], sol.u.values))
    return SirenSolution(sol.t[[index]], data)
end

"""
    (sol::AbstractSirenSolution)(t::Real)

Interpolate the solution at a given time `t` using linear interpolation where possible.

# Arguments
- `sol::AbstractSirenSolution`: The solution object containing time points and state histories.
- `t::Real`: The time at which to interpolate the solution. Must be within `[sol.t[1], sol.t[end]]`.

# Returns
- `AbstractSirenSolution`: A new [SirenSolution](@ref) object containing the interpolated state at time `t`.

# Interpolation Rules
- For numeric states and numeric arrays: Uses linear interpolation between saved time points.
- For non-numeric states (e.g., Agents.jl models, objects): Uses constant interpolation
    (returns the state from the last saved time point before or at `t`).

# Examples
```julia
sol(2.5)  # Interpolate solution at time t=2.5
```
"""
function (sol::AbstractSirenSolution)(t::Real)
    if t < sol.t[1] || t > sol.t[end]
        throw(BoundsError(
            "Time $t is out of bounds for the solution range " *
            "[$(sol.t[1]), $(sol.t[end])]."
        ))
    end
    function interpolate_state(state1, state2, alpha)
        interp_state1 = (state1 isa AbstractArray && eltype(state1) <: Number) ||
                        (state1 isa Number)
        interp_state2 = (state2 isa AbstractArray && eltype(state2) <: Number) ||
                        (state2 isa Number)
        if interp_state1 && interp_state2
            return state1 .+ alpha .* (state2 .- state1)
        end
        return state1
    end
    lb = findlast(x -> x <= t, sol.t)
    ub = findfirst(x -> x >= t, sol.t)
    if lb == ub && !isnothing(lb)
        return sol[lb]
    end
    change = (t - sol.t[lb]) / (sol.t[ub] - sol.t[lb])
    data = SirenSolutionData(sol.u.keys, map(v -> interpolate_state(v[lb], v[ub], change), sol.u.values))
    return SirenSolution([t], data)
end

function state_type(sirenInt, cv)
    state = getstate(sirenInt, cv)
    return typeof(state)
end

function SirenSolutionData(sirenInt::AbstractSirenIntegrator)
    keys = Tuple(sirenInt.save_vars)
    values = Tuple(Vector{state_type(sirenInt, key)}() for key in keys)
    return SirenSolutionData(keys, values)
end

function Base.length(sol::SirenSolutionData)
    return length(sol.keys)
end

function Base.iterate(sol::SirenSolutionData, state=1)
    if state > length(sol)
        return nothing
    end
    return (sol.keys[state], sol.values[state]), state + 1
end

function Base.haskey(sol::SirenSolutionData, key)
    return key in sol.keys
end

function Base.get(sol::SirenSolutionData, key, default)
    idx = findfirst(isequal(key), sol.keys)
    if isnothing(idx)
        return default
    end
    return sol.values[idx]
end
