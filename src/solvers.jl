using CommonSolve

"""
    MinimumTimeStepper() <: AbstractMermaidSolver

A solver that advances the Mermaid integrator by stepping to the next event.

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
struct MinimumTimeStepper <: AbstractMermaidSolver
end

function CommonSolve.step!(merInt::MermaidIntegrator, ::MinimumTimeStepper)
    # Update the current time
    min_t = Inf
    for (int, timescale) in zip(merInt.integrators, merInt.timescales)
        next_t = (gettime(int) + timestep(int)) * timescale
        if next_t < min_t
            min_t = next_t
        end
    end
    # Stop early if the user requested to save somewhere
    if merInt.saveat isa AbstractVector && any(merInt.currtime .< merInt.saveat .< min_t)
        min_t = first(merInt.saveat[merInt.saveat .> merInt.currtime])
    end
    merInt.currtime = min_t
    # Apply connections
    for conn in merInt.connectors
        if checkconnection(conn, merInt)
            runconnection!(merInt, conn)
        end
    end
    # Step the integrator
    for (int, timescale) in zip(merInt.integrators, merInt.timescales)
        if (gettime(int) + timestep(int)) * timescale <= nextfloat(merInt.currtime, 3)
            t_before = gettime(int)
            # Step the integrator
            step!(int)
            if gettime(int) <= t_before
                error("Component $(name(int)) failed to advance: time did not move forward from $t_before.")
            end
            # Force time synchronization after stepping to avoid floating point issues.
            # Especially important for handling multiple timescales to avoid errors stacking.
            if gettime(int) * timescale != merInt.currtime
                @assert prevfloat(merInt.currtime, 3) <= gettime(int) * timescale <= nextfloat(merInt.currtime, 3) "Floating point rounding is larger than expected. Please report this bug. $((gettime(int), timescale, merInt.currtime))"
                settime!(int, merInt.currtime / timescale)
            end
        end
    end
end
