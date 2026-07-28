"""
    MermaidSolution{X, Y} <: AbstractMermaidSolution

Stores the solution of a [MermaidProblem](@ref) over time.

# Fields
- `t::X`: Time points at which the solution is saved.
- `u::Y`: Dictionary mapping variables to their solution arrays.

# Interpolation

A solution can be interpolated at arbitrary times using callable syntax:

```julia
(sol::AbstractMermaidSolution)(t::Real)
```

This returns a new `MermaidSolution` with interpolated states at time `t`.

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
struct MermaidSolution{X, Y} <: AbstractMermaidSolution
    t::X
    u::Y
end

"""
    MermaidSolution(int::MermaidIntegrator) <: AbstractMermaidSolution

Create a [MermaidSolution](@ref) object initialized for the `save_vars`/variables in the
    given MermaidIntegrator.

# Arguments
- `int::MermaidIntegrator`: The integrator to extract solution structure from.

# Returns
- `MermaidSolution`: A new [MermaidSolution](@ref) object with empty time and state arrays
    for each variable to be saved.
"""
function MermaidSolution(int::AbstractMermaidIntegrator)
    u = Dict()
    for var in int.save_vars
        u[ConnectedVariable(var)] = []
    end
    return MermaidSolution([], u)
end

"""
    update_solution!(sol::MermaidSolution, merInt::MermaidIntegrator)

Update the [MermaidSolution](@ref) `sol` with the current time and state from the
    MermaidIntegrator.

# Arguments
- `sol::MermaidSolution`: The [MermaidSolution](@ref) to be updated.
- `merInt::MermaidIntegrator`: The integrator object providing the current time (`currtime`)
    and states to access via `getstate`.
"""
function update_solution!(sol::AbstractMermaidSolution, merInt::AbstractMermaidIntegrator)
    push!(sol.t, merInt.currtime)
    for key in keys(sol.u)
        push!(sol.u[key], getstate(merInt, key; copy = true))
    end
end

"""
    Base.getindex(sol::AbstractMermaidSolution, var::AbstractString)
    Base.getindex(sol::AbstractMermaidSolution, var::AbstractConnectedVariable)
    Base.getindex(sol::AbstractMermaidSolution, index::Int)

Get the solution for a variable `var` or at a time index `index` from a
    [MermaidSolution](@ref).

# Arguments
- `sol::AbstractMermaidSolution`: The solution object.
- `var::Union{AbstractString, AbstractConnectedVariable}`: The variable name, optionally
    with indices like `\"comp.var[1:3]\"` or `\"comp[2].var[4]\"`.
- `index::Int`: The time index (1-based) into the saved times.

# Returns
- If `var` is provided, returns a vector of saved states for that variable across all times.
- If `index` is provided, returns a new [MermaidSolution](@ref) containing only the data
    at that time index for each variable.

# Examples
```julia
sol[\"comp.var\"]        # All saved states for variable \"comp.var\"
sol[ConnectedVariable(\"comp[1].var\")]  # States for duplicated instance 1
sol[3]                 # Solution data at the 3rd saved time point
```
"""
function Base.getindex(sol::AbstractMermaidSolution, var::AbstractString)
    var = ConnectedVariable(var)
    return Base.getindex(sol, var)
end

function Base.getindex(sol::AbstractMermaidSolution, var::AbstractConnectedVariable)
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

function Base.getindex(sol::AbstractMermaidSolution, index::Integer)
    if index < 1 || index > length(sol.t)
        throw(BoundsError(sol.t, index))
    end
    return MermaidSolution(
        [sol.t[index]], Dict([var => sol.u[var][index] for var in keys(sol.u)]))
end

"""
    (sol::AbstractMermaidSolution)(t::Real)

Interpolate the solution at a given time `t` using linear interpolation where possible.

# Arguments
- `sol::AbstractMermaidSolution`: The solution object containing time points and state histories.
- `t::Real`: The time at which to interpolate the solution. Must be within `[sol.t[1], sol.t[end]]`.

# Returns
- `AbstractMermaidSolution`: A new [MermaidSolution](@ref) object containing the interpolated state at time `t`.

# Interpolation Rules
- For numeric states and numeric arrays: Uses linear interpolation between saved time points.
- For non-numeric states (e.g., Agents.jl models, objects): Uses constant interpolation
    (returns the state from the last saved time point before or at `t`).

# Examples
```julia
sol(2.5)  # Interpolate solution at time t=2.5
```
"""
function (sol::AbstractMermaidSolution)(t::Real)
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
    if lb == ub
        return sol[lb]
    end
    change = (t - sol.t[lb]) / (sol.t[ub] - sol.t[lb])
    states = Dict()
    for var in keys(sol.u)
        states[var] = interpolate_state(sol.u[var][lb], sol.u[var][ub], change)
    end
    return MermaidSolution([t], states)
end
