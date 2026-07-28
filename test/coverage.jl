# Arbitrary tests for no other reason than to fix weird coverage cases

@testitem "step!(::AbstractComponentIntegrator)" begin
    struct A <: AbstractComponentIntegrator
    end
    a = A()
    step!(a)
end

@testitem "init(::AbstractComponent)" begin
    struct A <: AbstractComponent
    end
    a = A()
    init(a)
end
