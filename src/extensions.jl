struct DEComponent{A, B, C, D, E, F} <: AbstractTimeDependentComponent
    model::A
    name::B
    state_names::C
    timestep::D
    alg::E
    intkwargs::F
end

"""
$(TYPEDEF)
"""
mutable struct DEComponentIntegrator{A, B} <: AbstractComponentIntegrator
    integrator::A
    component::B
end

struct JumpComponent{A, B, C, D, E, F} <: AbstractTimeDependentComponent
    model::A
    name::B
    state_names::C
    timestep::D
    alg::E
    intkwargs::F
end

"""
$(TYPEDEF)
"""
mutable struct JumpComponentIntegrator{A, B} <: AbstractComponentIntegrator
    integrator::A
    component::B
end

struct TrixiParticlesComponent{A, B, C, D, E, F, G} <: AbstractTimeDependentComponent
    model::A
    semi::B
    name::C
    state_names::D
    timestep::E
    alg::F
    intkwargs::G
end

"""
$(TYPEDEF)
"""
mutable struct TrixiParticlesComponentIntegrator{A, B} <: AbstractComponentIntegrator
    integrator::A
    component::B
end

struct AgentsComponent{A, B, C, D} <: AbstractTimeDependentComponent
    model::A
    name::B
    state_names::C
    timestep::D
end

"""
$(TYPEDEF)
"""
mutable struct AgentsComponentIntegrator{A, B} <: AbstractComponentIntegrator
    integrator::A
    time::Float64
    component::B
end

struct MOLComponent{A, B, C, D, E, F} <: AbstractTimeDependentComponent
    model::A
    name::B
    state_names::C
    timestep::D
    alg::E
    intkwargs::F
end

"""
$(TYPEDEF)
"""
mutable struct MOLComponentIntegrator{A, B} <: AbstractComponentIntegrator
    integrator::A
    component::B
end

struct SurrogateComponent{A, B, C, D, E, F, G, H, I} <: AbstractTimeDependentComponent
    component::A
    name::B
    surrogate::C
    timestep::D
    state_names::E
    lower_bound::F
    upper_bound::G
    n_samples::H
    kwargs::I
end

"""
$(TYPEDEF)
"""
mutable struct SurrogateComponentIntegrator{A, B, C, D, E} <: AbstractComponentIntegrator
    integrator::A
    component::B
    state::C
    time::D
    surrogate::E
end
