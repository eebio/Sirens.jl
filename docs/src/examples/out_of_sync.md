# Out of sync computation

So far, we have only seen one of Mermaid's solvers, the [MinimumTimeStepper](@ref).
This solver is the simplest to understand, taking global time steps and solving all components up until the next step would put them ahead of the global time.
This works fine for serial computations, but can lead to wasted resources if multiple cores are available.
For example, if we have one component which doesn't have any inputs (but does have outputs), it could be solved entirely, and doesn't need to be kept in sync with the global time.
This could be used to ensure that all available cores are working, with most dedicated to solving the current global time step while the remainder solve future time steps for this component.

We can do this in Mermaid with the `QueueStepper`.
This solver creates a queue of all components which can be stepped, and assigns them to cores as they become available.
After each component step has completed, we can find all components that depend on it and (assuming they aren't reliant on any other components/steps that need to run) add them to the queue.

## Solving with out of sync computations

TODO CFD flow informing Agents of enzymes, both informing a PDE of some chemical reactions
