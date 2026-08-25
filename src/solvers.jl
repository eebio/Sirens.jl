using CommonSolve

# There are a few instances of unfurled tuples in the code. They are there for type
# stability, rather than having an iterator variable with union types. This helps with
# dispatch to the correct component interface methods.

"""
    MinimumTimeStepper() <: AbstractSirenSolver

A solver that advances the [SirenIntegrator](@ref) by stepping to the next event.

# Algorithm
The minimum stepper chooses the smallest upcoming value of `(local_time + timestep) * timescale`
across all components. It then:

1. Applies connectors whose input global times are no later than their output global times.
2. Steps all components whose next local event reaches the new global time.
3. Adjusts component times after stepping to mitigate floating-point roundoff accumulation.

# Timestepping and Multirate Behavior
For component `i` with timescale `s_i`, the global time is `t_global = s_i * t_local`.

The minimum stepper guarantees that possible connection applications cannot be jumped over.
If the method synchronized at different timepoints, a connection that could have been
applied if time were treated continuously might be missed.

# Connections
Connections use the most recently available state at each synchronization event. They do
not interpolate between component states and do not guarantee identical local times across
components.

See also [Connector](@ref).
"""
struct MinimumTimeStepper <: AbstractSirenSolver
end

@inline _min_next_time(::Tuple{}, timescales::Vector{Float64}, i::Int, min_t) = min_t
@inline function _min_next_time(integrators::Tuple, timescales::Vector{Float64}, i::Int, min_t)
    int = first(integrators)
    next_t = (gettime(int) + timestep(int)) * timescales[i]
    min_t = next_t < min_t ? next_t : min_t
    return _min_next_time(Base.tail(integrators), timescales, i + 1, min_t)
end

@inline _apply_connectors!(::Tuple{}, sirenInt::AbstractSirenIntegrator) = nothing
@inline function _apply_connectors!(connectors::Tuple, sirenInt::AbstractSirenIntegrator)
    conn = first(connectors)
    if isexecutable(conn) && checkconnection(conn, sirenInt)
        runconnection!(sirenInt, conn)
    end
    return _apply_connectors!(Base.tail(connectors), sirenInt)
end

function CommonSolve.step!(sirenInt::SirenIntegrator, ::MinimumTimeStepper)
    # Update the current time
    min_t = _min_next_time(sirenInt.integrators, sirenInt.timescales, 1, Inf)
    # Stop early if the user requested to save somewhere
    if sirenInt.saveat isa AbstractVector && any(sirenInt.currtime .< sirenInt.saveat .< min_t)
        min_t = first(sirenInt.saveat[sirenInt.saveat .> sirenInt.currtime])
    end
    sirenInt.currtime = min_t
    # Apply connections
    _apply_connectors!(sirenInt.connectors, sirenInt)
    # Step the integrator
    _step_components!(sirenInt.integrators, sirenInt.timescales, 1, sirenInt.currtime)
    return nothing
end

@inline _step_components!(::Tuple{}, timescales::Vector{Float64}, i::Int, currtime::Float64) = nothing
@inline function _step_components!(integrators::Tuple, timescales::Vector{Float64}, i::Int, currtime::Float64)
    int = first(integrators)
    timescale = timescales[i]
    if (gettime(int) + timestep(int)) * timescale <= nextfloat(currtime, 3)
        t_before = gettime(int)
        step!(int)
        if gettime(int) <= t_before
            error("Component $(name(int)) failed to advance: time did not move forward from $t_before.")
        end
        # Force time synchronization after stepping to avoid floating point issues.
        # Especially important for handling multiple timescales to avoid errors stacking.
        if gettime(int) * timescale != currtime
            @assert prevfloat(currtime, 3) <= gettime(int) * timescale <= nextfloat(currtime, 3) "Floating point rounding is larger than expected. Please report this bug. $((gettime(int), timescale, currtime))"
            settime!(int, currtime / timescale)
        end
    end
    return _step_components!(Base.tail(integrators), timescales, i + 1, currtime)
end
