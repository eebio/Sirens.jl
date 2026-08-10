using DocStringExtensions

"""
$(TYPEDEF)
"""
abstract type AbstractComponent end

"""
$(TYPEDEF)
"""
abstract type AbstractTimeIndependentComponent <: AbstractComponent end

"""
$(TYPEDEF)
"""
abstract type AbstractTimeDependentComponent <: AbstractComponent end

"""
$(TYPEDEF)
"""
abstract type AbstractComponentIntegrator end

"""
$(TYPEDEF)
"""
abstract type AbstractSirenSolver end

"""
$(TYPEDEF)
"""
abstract type AbstractSirenIntegrator end

"""
$(TYPEDEF)
"""
abstract type AbstractSirenProblem end

"""
$(TYPEDEF)
"""
abstract type AbstractSirenSolution end

"""
$(TYPEDEF)
"""
abstract type AbstractConnectedVariable end

"""
$(TYPEDEF)
"""
abstract type AbstractConnector end
