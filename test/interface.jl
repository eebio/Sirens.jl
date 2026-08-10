@testsnippet interface1 begin
    using Sirens

    struct TestComponent <: AbstractComponent
        timestep::Float64
        name::String
    end

    # An integrator that includes component as a field
    mutable struct TestIntegrator <: AbstractComponentIntegrator
        component::TestComponent
        state::Float64
    end

    function init(c::TestComponent)
        return TestIntegrator(c, 0.0)
    end

    function step!(compInt::TestIntegrator)
        compInt.state += compInt.component.timestep
    end

    function Sirens.getstate(compInt::TestIntegrator, key)
        if key.variable == "#time"
            return compInt.state
        end
        return compInt.state
    end

    function Sirens.getstate(compInt::TestIntegrator)
        return compInt.state
    end

    function Sirens.setstate!(compInt::TestIntegrator, key, value)
        if first(key.variable) == '#'
            if key.variable == "#time"
                compInt.state = value
                return nothing
            end
        end
        compInt.state = value
    end

    function Sirens.setstate!(compInt::TestIntegrator, value)
        compInt.state = value
    end

    function Sirens.variables(component::TestComponent)
        return ["#time"]
    end
end

@testitem "interface with component field" setup=[interface1] begin
    component = TestComponent(0.1, "Test Component")
    int = init(component)
    @test gettime(int) == 0.0
    @test timestep(int) == 0.1
    @test name(int) == "Test Component"
    step!(int)
    @test gettime(int) == 0.1
    settime!(int, 2.0)
    @test gettime(int) == 2.0
    @test getstate(int) == 2.0
    setstate!(int, ConnectedVariable("a.b"), 5.0)
    @test getstate(int) == 5.0
    @test variables(int) == ["#time"]
end

@testsnippet interface2 begin
    using Sirens

    struct TestComponent2 <: AbstractComponent
        timestep_new_name::Float64
        name_new_name::String
    end

    # An integrator that includes component as a field
    mutable struct TestIntegrator2 <: AbstractComponentIntegrator
        component_new_name::TestComponent2
        state::Float64
    end

    function init(c::TestComponent2)
        return TestIntegrator2(c, 0.0)
    end

    function step!(compInt::TestIntegrator2)
        compInt.state += compInt.component_new_name.timestep_new_name
    end

    function Sirens.getstate(compInt::TestIntegrator2, key)
        if key.variable == "#time"
            return compInt.state
        end
        return compInt.state
    end

    function Sirens.getstate(compInt::TestIntegrator2)
        return compInt.state
    end

    function Sirens.setstate!(compInt::TestIntegrator2, key, value)
        if first(key.variable) == '#'
            if key.variable == "#time"
                compInt.state = value
                return nothing
            end
        end
        compInt.state = value
    end

    function Sirens.setstate!(compInt::TestIntegrator2, value)
        compInt.state = value
    end

    function Sirens.variables(component::Union{TestComponent2, TestIntegrator2})
        return ["#time"]
    end

    function Sirens.name(component::Union{TestComponent2, TestIntegrator2})
        return "Test Component"
    end

    function Sirens.timestep(component::Union{TestComponent2, TestIntegrator2})
        return 0.1
    end
end

@testitem "interface without component field" setup=[interface2] begin
    component = TestComponent2(0.1, "Test Component")
    int = init(component)
    @test int isa TestIntegrator2
    @test gettime(int) == 0.0
    @test timestep(int) == 0.1
    @test name(int) == "Test Component"
    step!(int)
    @test gettime(int) == 0.1
    settime!(int, 2.0)
    @test gettime(int) == 2.0
    @test getstate(int) == 2.0
    setstate!(int, ConnectedVariable("a.b"), 5.0)
    @test getstate(int) == 5.0
    @test variables(int) == ["#time"]
end
