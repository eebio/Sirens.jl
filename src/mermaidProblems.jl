using CommonSolve

"""
    MermaidProblem <: AbstractMermaidProblem
    MermaidProblem(components, connectors, tspan, timescales=ones(length(components)))
    MermaidProblem(;
        components::Union{Tuple, Vector},
        connectors::Union{Tuple, Vector},
        tspan::Tuple{Float64, Float64},
        timescales::Vector{Float64}=ones(length(components)))

Defines a Mermaid hybrid simulation problem.

# Arguments
- `components::Union{Tuple, Vector}`: Tuple or Vector of [Components](@ref AbstractComponent). Order is significant
    because it determines stepping order when multiple components can be stepped together.
    Component names must be unique. Using a tuple preserves type information for each element.
- `connectors::Union{Tuple, Vector}`: Tuple or Vector of [Connectors](@ref Connector). Order
    is significant; connectors are applied in order, and later connectors can observe
    changes made by earlier ones. Using a tuple preserves type information for each element.
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
struct MermaidProblem{C<:Tuple,CC<:Tuple} <: AbstractMermaidProblem
    components::C
    connectors::CC
    tspan::NTuple{2,Float64}
    timescales::Vector{Float64}

    function MermaidProblem(components, connectors, tspan, timescales)

        # Handle types
        # Components and connectors should be tuples for type stability
        components = components isa Tuple ? components : tuple(components...)
        connectors = connectors isa Tuple ? connectors : tuple(connectors...)

        # Validate tspan length and convert to proper type
        if length(tspan) < 2
            throw(ArgumentError("tspan must have exactly 2 elements, got $(length(tspan))"))
        end
        tspan::NTuple{2,Float64} = (Float64(tspan[1]), Float64(tspan[2]))

        # timescales should be a vector of Float64 and same length as components
        @assert length(timescales) == length(components) "Length of timescales must match number of components."
        timescales = timescales isa Vector{Float64} ? timescales : Float64[convert(Float64, ts) for ts in timescales]

        # Check that component names are unique
        names = [name(comp) for comp in components]
        if length(names) != length(unique(names))
            error("Component names must be unique. Found duplicate names: $(names)")
        end

        # Check for algebraic loops in the connections
        report_algebraic_loop(connectors)

        return new{typeof(components), typeof(connectors)}(components, connectors, tspan, timescales)
    end
end

function MermaidProblem(; components, connectors, tspan, timescales=ones(length(components)))
    return MermaidProblem(components, connectors, tspan, timescales)
end

function MermaidProblem(components, connectors, tspan)
    return MermaidProblem(components, connectors, tspan, ones(length(components)))
end

"""
    MermaidIntegrator <: AbstractMermaidIntegrator
    MermaidIntegrator(;
        integrators::Tuple,
        connectors::Tuple,
        tspan::Tuple{Float64, Float64},
        currtime::Float64,
        alg::AbstractMermaidSolver,
        save_vars::Vector{<:AbstractString},
        saveat::Union{Function, AbstractVector},
        timescales::Vector{Float64})

Created using `init(prob::MermaidProblem, alg::AbstractMermaidSolver; save_vars=[])`. All fields are considered internal.
"""
mutable struct MermaidIntegrator{
    I<:Tuple,CC<:Tuple,X<:AbstractMermaidSolver,S<:Union{Function,AbstractVector}} <:
               AbstractMermaidIntegrator
    integrators::I
    connectors::CC
    tspan::Tuple{Float64, Float64}
    currtime::Float64
    alg::X
    save_vars::Vector{<:AbstractString}
    saveat::S
    timescales::Vector{Float64}

    function MermaidIntegrator(integrators::I, connectors::CC, tspan::Tuple{Float64, Float64}, currtime::Float64, alg::X, save_vars::Vector{<:AbstractString}, saveat::S, timescales::Vector{<:Real}) where {I<:Tuple,CC<:Tuple,X<:AbstractMermaidSolver,S<:Union{Function,AbstractVector}}
        return new{I,CC,X,S}(integrators, connectors, tspan, currtime, alg, save_vars, saveat, timescales)
    end
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
    integrators = map(c -> something(init(c)), prob.components)

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

    # Validate tspan length
    if length(prob.tspan) != 2
        throw(ArgumentError("tspan must have exactly 2 elements, got $(length(prob.tspan))"))
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
    return _getstate_by_name(merInt.integrators, key; kwargs...)
end

@inline _getstate_by_name(::Tuple{}, key::AbstractConnectedVariable; kwargs...) = nothing
@inline function _getstate_by_name(integrators::Tuple, key::AbstractConnectedVariable; kwargs...)
    integrator = first(integrators)
    if name(integrator) == key.component
        return getstate(integrator, key; kwargs...)
    end
    return _getstate_by_name(Base.tail(integrators), key; kwargs...)
end

function gettime(merInt::AbstractMermaidIntegrator)
    # Get the current time of the integrator
    return merInt.currtime
end

function setstate!(merInt::AbstractMermaidIntegrator, key::AbstractConnectedVariable, value)
    _setstate_by_name!(merInt.integrators, key, value)
    return nothing
end

@inline _setstate_by_name!(::Tuple{}, key::AbstractConnectedVariable, value) = nothing
@inline function _setstate_by_name!(integrators::Tuple, key::AbstractConnectedVariable, value)
    integrator = first(integrators)
    if name(integrator) == key.component
        setstate!(integrator, key, value)
        return nothing
    end
    return _setstate_by_name!(Base.tail(integrators), key, value)
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
