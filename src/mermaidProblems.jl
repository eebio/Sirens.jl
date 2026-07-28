using CommonSolve

"""
    MermaidProblem <: AbstractMermaidProblem
    MermaidProblem(;
        components::Vector{AbstractComponent},
        connectors::Vector{AbstractConnector},
        tspan::Tuple{Float64, Float64},
        timescales::Vector{Float64}=ones(length(components)))

Defines a Mermaid hybrid simulation problem.

# Keyword Arguments
- `components::Vector{<:AbstractComponent}`: Vector of [Components](@ref AbstractComponent). Order is significant
    because it determines stepping order when multiple components can be stepped together.
    Component names must be unique.
- `connectors::Vector{<:AbstractConnector}`: Vector of [Connectors](@ref Connector). Order
    is significant; connectors are applied in order, and later connectors can observe
    changes made by earlier ones.
- `tspan::Tuple{Float64, Float64}`: The time span of the simulation, from start to end time.
- `timescales::Vector{Float64}=ones(length(components))`: Timescales for each component.
    For component `i`, global time is computed as `t_global[i] = timescales[i] * t_local[i]`.
    A component with timescale 0.1 advances ten local time units per one global time unit.
    This allows components using different time units to be connected in a single
    simulation.

# Notes on Ordering
- `components` order determines stepping priority when multiple components are ready.
- `connectors` order is critical. Connectors are applied before component steps, in the
    order given. A connector is eligible only when every input is no later than every
    output in global time. Later connectors see changes made by earlier connectors. This is
    particularly important for setting `#ids` and `#init_states` in a
    [DuplicatedComponent](@ref).
"""
@kwdef struct MermaidProblem <: AbstractMermaidProblem
    components::Vector{AbstractComponent}
    connectors::Vector{AbstractConnector}
    tspan::Tuple{Float64, Float64}
    timescales::Vector{Float64} = ones(length(components))
end

"""
    MermaidIntegrator <: AbstractMermaidIntegrator
    MermaidIntegrator(;
        integrators::Vector{<:AbstractComponentIntegrator},
        connectors::Vector{<:AbstractConnector},
        tspan::Tuple{Float64, Float64},
        currtime::Float64,
        alg::AbstractMermaidSolver,
        save_vars::Vector{<:AbstractString},
        saveat::Union{Function, AbstractVector},
        timescales::Vector{Float64})

Created using `init(prob::MermaidProblem, alg::AbstractMermaidSolver; save_vars=[])`. All fields are considered internal.
"""
mutable struct MermaidIntegrator{
    X <: AbstractMermaidSolver, S <: Union{Function, AbstractVector}} <:
               AbstractMermaidIntegrator
    integrators::Vector{<:AbstractComponentIntegrator}
    connectors::Vector{<:AbstractConnector}
    tspan::Tuple{Float64, Float64}
    currtime::Float64
    alg::X
    save_vars::Vector{<:AbstractString}
    saveat::S
    timescales::Vector{Float64}
end

"""
    init(prob::AbstractMermaidProblem, alg::AbstractMermaidSolver;
    save_vars = nothing, saveat = nothing)

Defines the integrator for a Mermaid hybrid simulation.

# Arguments
- `prob::AbstractMermaidProblem`: The problem to be solved.
- `alg::AbstractMermaidSolver`: The Mermaid solver algorithm to be used.
- `save_vars`: Variables to be saved during the simulation. Options include:
    - `nothing` (default): Save all non-special variables (those not starting with '#').
    - `:all`: Save all variables, including special variables.
    - `:none` or `String[]`: Save no variables (time is still recorded).
    - `Vector{String}`: A vector of connected variable fullnames to save, including optional
      indices like `"forest.life[1]"` or `"tree[1:10].life"`.
- `saveat`: When to save the variables during the simulation. Options include:
    - `nothing` (default): Save after initialization and after every Mermaid event.
    - A number `Δt`: Save at times `tspan[1]:Δt:tspan[2]`.
    - A vector of times: Save at exactly these time points.
    - A function `(integrator, t) -> Bool`: Save when it returns true (checked at scheduled stops).

# Returns
- `MermaidIntegrator`: A mutable integrator ready for solving.
"""
function CommonSolve.init(prob::AbstractMermaidProblem, alg::AbstractMermaidSolver;
        save_vars = nothing, saveat = nothing)
    # Initialize the solver
    integrators = [init(c) for c in prob.components]

    # Process save_vars
    if isnothing(save_vars) || save_vars == :all
        tmp = String[]
        for int in integrators
            for var in variables(int)
                if var[1] != '#' || save_vars == :all
                    push!(tmp, string(name(int), ".", var))
                end
            end
        end
        save_vars = tmp
    end
    if (save_vars isa AbstractVector && length(save_vars) == 0) || save_vars == :none
        save_vars = String[]
    end

    # Process saveat
    if isnothing(saveat)
        saveat = (integrator, t) -> true
    end
    if saveat isa Number
        saveat = prob.tspan[1]:saveat:prob.tspan[2]
    end
    return MermaidIntegrator(
        integrators, prob.connectors, prob.tspan, 0.0, alg, save_vars, saveat, prob.timescales)
end

"""
    step!(int::AbstractMermaidIntegrator)

Advance the state of the integrator `int` by one time step.

# Arguments
- `int::Union{AbstractMermaidIntegrator, AbstractComponentIntegrator}`: The integrator to
    advance.
"""
function CommonSolve.step!(merInt::AbstractMermaidIntegrator)
    step!(merInt, merInt.alg)
end

"""
    solve!(merInt::AbstractMermaidIntegrator)

Solves the problem using the MermaidIntegrator by advancing it until the end of the
time span, recording solutions according to the `saveat` configuration.

# Arguments
- `merInt::AbstractMermaidIntegrator`: The integrator to be solved.

# Returns
- `MermaidSolution`: The [solution](@ref MermaidSolution) of the problem, containing
  saved times and states.

# Behavior
- Records initial state if `saveat` is satisfied at `t=tspan[1]`.
- Repeatedly calls `step!(integrator)` until `currtime >= tspan[2]`.
- Records state after each step if `saveat` is satisfied.
"""
function CommonSolve.solve!(merInt::AbstractMermaidIntegrator)
    sol = MermaidSolution(merInt)
    if should_save(merInt, merInt.saveat)
        update_solution!(sol, merInt)
    end
    while merInt.currtime < merInt.tspan[2]
        step!(merInt)
        if should_save(merInt, merInt.saveat)
            update_solution!(sol, merInt)
        end
    end
    return sol
end

function should_save(merInt::AbstractMermaidIntegrator, saveat::AbstractVector)
    if merInt.currtime in saveat
        return true
    else
        return false
    end
end

function should_save(merInt::AbstractMermaidIntegrator, saveat::Function)
    return saveat(merInt, merInt.currtime)
end

function getstate(merInt::AbstractMermaidIntegrator, key::AbstractConnectedVariable; kwargs...)
    # Get the state of the component based on the key
    for integrator in merInt.integrators
        if name(integrator) == key.component
            return getstate(integrator, key; kwargs...)
        end
    end
end

function gettime(merInt::AbstractMermaidIntegrator)
    # Get the current time of the integrator
    return merInt.currtime
end

function setstate!(merInt::AbstractMermaidIntegrator, key::AbstractConnectedVariable, value)
    # Set the state of the component based on the key
    for integrator in merInt.integrators
        if name(integrator) == key.component
            setstate!(integrator, key, value)
            return nothing
        end
    end
end

"""
    gettime(merInt::AbstractComponentIntegrator)

Get the current time of the integrator.

# Arguments
- `int::AbstractComponentIntegrator`: The integrator whose time is to be retrieved.

# Returns
- The current time of the integrator.
"""
function gettime(int::AbstractComponentIntegrator)
    getstate(
        int, ConnectedVariable(name(int), "#time", nothing, nothing))
end

"""
    settime!(merInt::AbstractComponentIntegrator, t)

Set the current time of the integrator.

# Arguments
- `int::AbstractComponentIntegrator`: The integrator whose time is to be set.
- `t`: The time to set.
"""
function settime!(int::AbstractComponentIntegrator, t)
    setstate!(int,
        ConnectedVariable(name(int), "#time", nothing, nothing), t)
end

"""
    variables(integrator::AbstractComponent)
    variables(integrator::AbstractComponentIntegrator)

Get the variables names of the component or integrator that can be accessed through getstate
    and setstate!. This includes special variables like `#time`.
"""
variables(integrator::AbstractComponentIntegrator) = variables(integrator.component)

function getstate(args...; copy = false, kwargs...)
    if copy
        return deepcopy(getstate(args...; kwargs...))
    else
        return getstate(args...; kwargs...)
    end
end

"""
    timestep(int::AbstractComponent)
    timestep(comp::AbstractComponentIntegrator)

Get the proposed time step of the integrator or component. It can depend on the current
    state.
"""
timestep(comp::AbstractComponent) = comp.timestep
timestep(int::AbstractComponentIntegrator) = timestep(int.component)

"""
    name(int::AbstractComponentIntegrator)
    name(comp::AbstractComponent)

Get the name of the integrator or component.
"""
name(comp::AbstractComponent) = comp.name
name(int::AbstractComponentIntegrator) = name(int.component)
