# ModelingToolkit Integration

Similarly to Sirens, [ModelingToolkit](@extref ModelingToolkit index) also allows specifying models as components and then connecting them together.
However, the methods used are different.
For an overview of these differences, you can see [Is Sirens right for me?](@ref).
In summary, if it is possible to connect your components through ModelingToolkit, it is likely better to do that rather than through Sirens.
In order to simplify connected ModelingToolkit systems in Sirens, you can create `ModelingToolkitComponents` for all of your ModelingToolkit models, and specify the connections through Sirens.
Sirens will then figure out which `ModelingToolkitComponents` can be connected together in the [SirenProblem](@ref), perform the connections, generate the model and solve it.

## ModelingToolkitComponents
TODO
