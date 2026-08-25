# External Components

While there are many different modeling tools in Julia that can become components in Sirens, some cases require libraries and packages from outside of the Julia ecosystem.
In those cases, we may still be able to connect them to Sirens as components.
So long as the [integrator interface](@ref "Sirens Interface") can still be defined, using [PythonCall](@extref PythonCall The-Julia-module-PythonCall), for example, the external model can be connected within Sirens.
