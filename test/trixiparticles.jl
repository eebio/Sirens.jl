"""
MIT License

Copyright (c) 2023-present The TrixiParticles.jl Authors (see AUTHORS.md)
Copyright (c) 2023-present Helmholtz-Zentrum hereon GmbH, Institute of Surface Science

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

@testsnippet trixisim begin
    # A portion of this code is adapted from the TrixiParticles.jl examples under the above
    # licence.

    # ==========================================================================================
    # 2D Hydrostatic Water Column Simulation
    #
    # This example simulates a column of water at rest in a tank under gravity.
    # It is a basic test case to verify hydrostatic pressure distribution and stability.
    # ==========================================================================================

    using TrixiParticles
    using OrdinaryDiffEq
    using OrdinaryDiffEqLowStorageRK

    # ==========================================================================================
    # ==== Resolution
    fluid_particle_spacing = 0.05

    # Make sure that the kernel support of fluid particles at a boundary is always fully sampled
    boundary_layers = 3

    # ==========================================================================================
    # ==== Experiment Setup
    gravity = 9.81
    tspan = (0.0, 0.1)

    # Boundary geometry and initial fluid particle positions
    initial_fluid_size = (1.0, 0.9)
    tank_size = (1.0, 1.0)

    fluid_density = 1000.0
    sound_speed = 10.0
    state_equation = StateEquationCole(; sound_speed, reference_density = fluid_density,
        exponent = 7, clip_negative_pressure = false)

    tank = RectangularTank(
        fluid_particle_spacing, initial_fluid_size, tank_size, fluid_density,
        n_layers = boundary_layers, acceleration = (0.0, -gravity),
        state_equation = state_equation)

    # ==========================================================================================
    # ==== Fluid
    smoothing_length = 1.2 * fluid_particle_spacing
    smoothing_kernel = SchoenbergCubicSplineKernel{2}()

    alpha = 0.02
    viscosity_fluid = ArtificialViscosityMonaghan(alpha = alpha, beta = 0.0)

    fluid_density_calculator = ContinuityDensity()

    # This is to set acceleration with `trixi_include`
    system_acceleration = (0.0, -gravity)
    fluid_system = WeaklyCompressibleSPHSystem(tank.fluid; density_calculator = fluid_density_calculator,
        state_equation = state_equation, smoothing_kernel = smoothing_kernel,
        smoothing_length = smoothing_length, viscosity = viscosity_fluid,
        acceleration = system_acceleration,
        source_terms = nothing)

    # ==========================================================================================
    # ==== Boundary

    # This is to set another boundary density calculation with `trixi_include`
    boundary_density_calculator = AdamiPressureExtrapolation()

    # This is to set wall viscosity with `trixi_include`
    viscosity_wall = nothing
    boundary_model = BoundaryModelDummyParticles(tank.boundary.density, tank.boundary.mass,
        state_equation = state_equation,
        boundary_density_calculator,
        smoothing_kernel, smoothing_length,
        viscosity = viscosity_wall)
    boundary_system = WallBoundarySystem(tank.boundary, boundary_model,
        prescribed_motion = nothing)

    # ==========================================================================================
    # ==== Simulation
    semi = Semidiscretization(fluid_system, boundary_system,
        parallelization_backend = PolyesterBackend())
    ode = semidiscretize(semi, tspan)

    # Use a Runge-Kutta method with automatic (error based) time step size control
    sol_trixi = solve(ode, RDPK3SpFSAL35(); saveat = 0.002, tstops = 0.002:0.002:tspan[2])
end

@testitem "single trixi particles sim" setup = [trixisim] begin
    using TrixiParticles
    using OrdinaryDiffEq
    using Mermaid

    comp = TrixiParticlesComponent(semi, RDPK3SpFSAL35(); name = "TrixiParticles Component", timestep = 0.002)
    mp = MermaidProblem(components = [comp], connectors = [], tspan = tspan)
    alg = MinimumTimeStepper()
    sol_mermaid = solve(mp, alg; save_vars = ["TrixiParticles Component.#state"])
    a = [sol_mermaid(i)["TrixiParticles Component.#state"] for i in 0:0.1:tspan[2]]
    b = [sol_trixi(i) for i in 0:0.1:tspan[2]]
    @test a ≈ b
end

@testitem "coupled trixi particles sim with interpolation" setup = [trixisim] begin
    using TrixiParticles
    using OrdinaryDiffEq
    using OrdinaryDiffEqLowOrderRK
    using OrdinaryDiffEqLowStorageRK
    using Mermaid

    comp = TrixiParticlesComponent(semi, RDPK3SpFSAL35(); name = "TrixiParticles Component", timestep = 0.002)

    function f1!(du, u, p, t)
        x, y = u
        du[1] = y
        du[2] = 0
    end
    prob1 = ODEProblem(f1!, [0.0, 0.0], tspan)
    comp2 = DEComponent(
        prob1, Euler();
        name = "ODE",
        timestep = 0.002,
        state_names = OrderedDict("integral" => 1, "pressure" => 2),
        intkwargs = (:adaptive => false, :dt => 0.002)
    )

    function pressure_interpolation(state, semi)
        v_ode, u_ode = state.x
        data = interpolate_points([0.5, 0.5], semi, semi.systems[1], v_ode, u_ode)
        return data.pressure[1]
    end

    conn = Connector(
        inputs = ["TrixiParticles Component.#state", "TrixiParticles Component.#semi"],
        outputs = ["ODE.pressure"],
        func = pressure_interpolation
    )

    mp = MermaidProblem(components = [comp, comp2], connectors = [conn], tspan = tspan)
    alg = MinimumTimeStepper()
    sol_mermaid = solve(mp, alg; save_vars = ["TrixiParticles Component.#state"])

    int = init(mp, alg)
    @test getstate(int, ConnectedVariable("ODE.pressure")) == 0.0
    @test getstate(int, ConnectedVariable("ODE.integral")) == 0.0
    step!(int)
    @test 3500.0*0.002 < getstate(int, ConnectedVariable("ODE.integral")) < 5000.0*0.002
    @test 3500.0 < getstate(int, ConnectedVariable("ODE.pressure")) < 5000.0
end

@testitem "state control" setup = [trixisim] begin
    using TrixiParticles
    using OrdinaryDiffEq
    using OrdinaryDiffEqLowStorageRK

    comp = TrixiParticlesComponent(
        semi, RDPK3SpFSAL35(); name = "TrixiParticles Component", timestep = 0.002,
        state_names = Dict("particle1velx" => 1, "particle1vely" => 2))
    int = init(comp)
    @test gettime(int) == 0.0
    step!(int)
    @test gettime(int) == 0.002
    settime!(int, 0.005)
    @test gettime(int) == 0.005
    step!(int)
    @test gettime(int) == 0.007

    getstate(int, ConnectedVariable("TrixiParticles Component.#semi")) == semi
    getstate(int, ConnectedVariable("TrixiParticles Component.#state")) == getstate(int)
    setstate!(int, ConnectedVariable("TrixiParticles Component.#state"), sol_trixi(0.08))
    settime!(int, 0.08)
    @test getstate(int) == sol_trixi(0.08)
    step!(int)
    @test getstate(int) ≈ sol_trixi(0.082) rtol=1e-6

    @test issetequal(variables(int), ["particle1velx", "particle1vely", "#time", "#semi", "#integrator", "#state"])

    @test getstate(int, ConnectedVariable("TrixiParticles Component.particle1velx")) == getstate(int)[1]
    @test getstate(int, ConnectedVariable("TrixiParticles Component.particle1vely")) == getstate(int)[2]
    setstate!(int, ConnectedVariable("TrixiParticles Component.particle1velx"), 0.5)
    @test getstate(int, ConnectedVariable("TrixiParticles Component.particle1velx")) == 0.5
    step!(int)

    # Test special variable #integrator
    @test "#integrator" in variables(int)
    integrator_copy = getstate(int, ConnectedVariable("TrixiParticles Component.#integrator"); copy = true)
    @test typeof(integrator_copy) <: SciMLBase.DEIntegrator
    @test typeof(integrator_copy.u) == typeof(getstate(int))
    state_before_step = copy(getstate(int))
    step!(int)
    state_after_step = getstate(int)
    @test state_after_step ≠ state_before_step
    # Restore integrator state
    setstate!(int, ConnectedVariable("TrixiParticles Component.#integrator"), integrator_copy)
    @test getstate(int) == state_before_step
end
