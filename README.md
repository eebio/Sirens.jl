# Mermaid.jl

![Mermaid.jl logo](https://raw.githubusercontent.com/eebio/Mermaid.jl/refs/heads/main/docs/src/assets/logo-full.svg)

[![Run tests](https://github.com/eebio/Mermaid.jl/actions/workflows/test.yml/badge.svg)](https://github.com/eebio/Mermaid.jl/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/eebio/Mermaid.jl/graph/badge.svg?token=XRLUZB8FQS)](https://codecov.io/gh/eebio/Mermaid.jl)

Mermaid.jl is a hybrid and multiscale simulation environment in Julia.

Complex simulations can be produced by connecting together components from a wide range of Julia modeling tools.

Its key features are:

1. It is particularly well suited towards hybrid (continuous and discrete time), multiscale and nested systems. With direct support for nesting models within other models (Agent-based models where each agent solves an ODE, for example).
2. Models can be specified as arbitrary Julia code, include calls to other programming languages such as C or Python.
3. Out-of-the-box support for Agents.jl, DifferentialEquations.jl (and related packages), Surrogates.jl, MethodOfLines.jl, and TrixiParticles.jl.
4. A simple integrator interface allows user-defined extensions to previously unsupported components.

## Getting started

Mermaid can be installed from Julia with:

```julia
using Pkg; Pkg.add("Mermaid")
```

We have a begginer friendly [tutorial](https://eebio.github.io/Mermaid.jl/dev/tutorial/), and guided examples for different features in Mermaid available in the [docs](https://eebio.github.io/Mermaid.jl/dev/).

We also have a few more complex, unguided examples in the [examples directory](https://github.com/eebio/Mermaid.jl/tree/main/examples).
