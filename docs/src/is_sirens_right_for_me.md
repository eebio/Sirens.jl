# Is Sirens right for me?

This page will walk through the benefits and drawbacks of using Sirens, what it can do, what it does well, what it can't do and what it does poorly.

## Comparison against ModelingToolkit.jl

ModelingToolkit.jl is an acausal modeling language, where you specify symbolic forms of your models, which can then be connected together, and compiled into a DifferentialEquations.jl problem.

In short, if your whole system can be expressed in ModelingToolkit and solved (*mostly* equivalently, the combined system can be solved in DifferentialEquations or JumpProcesses), then it is probably better solved through ModelingToolkit rather than Sirens. The acausal connections lead to better accuracy and stability of the final solve.

The most notable exception to this is multirate solvers. Sirens naturally has components solved through different solvers, on different (possibly adaptive) timescales. Multirate and multisolver functionality is limited in DifferentialEquations.

!!! warning "Multi-rate solvers"
    Using a multirate solver for differential equations typically results in lower-order accuracy for the connected variables. If you are unsure whether a multirate solver is suitable, it is likely better to favor the solver algorithms in DifferentialEquations and use ModelingToolkit to perform the connections.

If only part of the whole system can be expressed in ModelingToolkit, you may still be able to benefit from ModelingToolkit features. Combining the relevant components together through ModelingToolkit and then converting that `System` to a component to connect through Sirens allows you to benefit from all ModelingToolkit features possible, while still having the flexibility to connect outside the ModelingToolkit ecosystem.

## Comparison against other multi-cellular simulators

There are a range of different software options available for specifically simulating multi-cellular systems ([Morpheus](https://morpheus.gitlab.io/), [CompuCell3D](https://compucell3d.org/), [Chaste](https://chaste.github.io/), [Artistoo](https://artistoo.net/index.html), [Vivarium](https://vivariumlab.com/)).

There are differences between all of these in their speed, ease of use, range of features and user-extensibility.

In general though, Sirens is more easily user-extensible, gives finer control over the simulation but takes more effort to define and currently lacks the parallelisation and distributed computing features present in some of these softwares.

Sirens is also the only one of these written in Julia.

## Comparison against other discrete event simulation solvers

Sirens can also be viewed as a discrete event simulator (similar to other software like [SimPy](https://simpy.readthedocs.io/en/latest/) or [DiscreteEvents.jl](https://github.com/JuliaDynamics/DiscreteEvents.jl)).

Here, the key difference is that Sirens' focus is on hybrid systems (connecting discrete and continuous solvers). Sirens already comes predefined with ways to setup many continuous systems, that would otherwise need to be handled by the user in other discrete event simulators.
