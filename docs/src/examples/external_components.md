# External Components

While there are many different modeling tools in Julia that can become components in Mermaid, some cases require libraries and packages from outside of the Julia ecosystem.
In those cases, we may still be able to connect them to Mermaid as components.
So long as the [integrator interface](@ref "Mermaid Interface") can still be defined, using [PythonCall](@extref PythonCall The-Julia-module-PythonCall), for example, the external model can be connected within Mermaid.
