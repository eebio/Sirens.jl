using Documenter, Sirens, CommonSolve
using DocumenterInterLinks
# Load extensions to be documented
using Agents, OrdinaryDiffEq, MethodOfLines, Surrogates, Flux, TrixiParticles, JumpProcesses

links = InterLinks(
    "CommonSolve" => "https://docs.sciml.ai/CommonSolve/dev/",
    "DiffEq" => "https://docs.sciml.ai/DiffEqDocs/stable/",
    "ModelingToolkit" => "https://docs.sciml.ai/ModelingToolkit/stable/",
    "Symbolics" => "https://docs.sciml.ai/Symbolics/stable/",
    "MethodOfLines" => "https://docs.sciml.ai/MethodOfLines/dev/",
    "PythonCall" => "https://juliapy.github.io/PythonCall.jl/stable/"
)

PAGES = [
    "Introduction" => "index.md",
    "Tutorial" => "tutorial.md",
    "Examples" => [
        "examples/duplicated_components.md",
        "examples/advanced_duplicated_components.md",
        "examples/surrogates.md",
        "examples/algorithm_accuracy.md",
        "examples/algebraic_loops.md",
        #"examples/mtk.md",
        #"examples/out_of_sync.md",
        #"examples/spatial_maps.md",
        #"examples/external_components.md",
    ],
    "Sirens Interface" => "interface.md",
    "Is Sirens right for me?" => "is_sirens_right_for_me.md",
    "FAQ" => "FAQ.md",
    "API" => "API.md"
]

modules = [Sirens,
    Base.get_extension(Sirens, :AgentsExt),
    Base.get_extension(Sirens, :DiffEqExt),
    Base.get_extension(Sirens, :MethodOfLinesExt),
    Base.get_extension(Sirens, :SurrogatesExt),
    Base.get_extension(Sirens, :TrixiParticlesExt),
    Base.get_extension(Sirens, :JumpProcessesExt),
]

format = Documenter.HTML(assets = ["assets/logo.ico"])

makedocs(sitename = "Sirens.jl", format = format,
    repo = Remotes.GitHub("eebio", "Sirens.jl"), modules = modules, checkdocs = :exports,
    pages = PAGES, plugins = [links])

deploydocs(
    repo = "github.com/eebio/Sirens.jl",
)
