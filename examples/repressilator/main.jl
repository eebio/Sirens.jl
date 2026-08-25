using Sirens
using OrdinaryDiffEq
using StochasticDiffEq
using SymbolicIndexingInterface
using Catalyst
using CairoMakie

includet("repressilator.jl")
includet("improved.jl")
includet("cells.jl")
includet("growth.jl")
includet("nutrients.jl")

using .Repressilator
using .Improved
using .Growth
using .Nutrients

using Random
Random.seed!(123)

max_t = 15.0
use_improved = true

sde = Repressilator.sde_repressilator()
sde_improved = Improved.sde_improved_repressilator()
repressilator = sde.f.sys
improved = sde_improved.f.sys

agents = initialize_cell_model()

growth = Growth.ode_growth()
g_model = Growth.get_growth_model()

nutrient_prob, dsrs = Nutrients.get_nutrient_prob()

rep = DEComponent(sde,
    EM();
    name="repressilator",
    state_names=Dict("gfp" => variable_index(sde, :gfp),
        "growth_rate" => variable_index(sde, :gr), "volume" => variable_index(
            sde, :V)),
    timestep=agents.dt, intkwargs=(; save_everystep=false, maxiters=Inf))

rep_imp = DEComponent(sde_improved,
    EM();
    name="repressilator",
    state_names=Dict("gfp" => variable_index(improved, :gfp),
        "growth_rate" => variable_index(improved, :gr), "volume" => variable_index(
            improved, :V)),
    timestep=agents.dt, intkwargs=(; save_everystep=false, maxiters=Inf))

abm = AgentsComponent(agents;
    name="cells",
    state_names=Dict("gfp" => :gfp, "size" => :size, "nutrients" => :nuts,
        "space_nutrients" => :nutrients,
        "nut_import_rate" => :nut_import_rate, "nut_import_rate_space" =>
            :nutrient_import_rate),
    timestep=agents.dt
)

function var_index(s)
    return variable_index(nutrient_prob, ModelingToolkit.parse_variable(nutrient_prob.f.sys, s))
end

pde = DEComponent(nutrient_prob, Tsit5();
    name="PDE",
    state_names=Dict(), # Catalyst spatial doesn't support variable_index for spatial variables
    timestep=agents.dt, intkwargs=(; save_everystep=false, maxiters=Inf)
)

gro = DEComponent(growth,
    Rosenbrock23();
    name="growth",
    state_names=Dict(
        "s" => variable_index(growth.f.sys, :s), "λ" => growth.f.sys.λ,
        "mass" => growth.f.sys.M,
        "import" => growth.f.sys.ν_imp),
    timestep=agents.dt, intkwargs=(;
        maxiters=Inf, isoutofdomain=(u, p, t) -> any(x -> x < 0, u),
        save_everystep=false))

dup_r = DuplicatedComponent(rep, []; default_state=sde.u0)

dup_i = DuplicatedComponent(rep_imp, []; default_state=sde_improved.u0)

dup_g = DuplicatedComponent(gro, []; default_state=growth.u0)

conn_ids_1 = Connector(
    inputs=["cells.#ids"],
    outputs=["repressilator.#ids"]
)

conn_ids_2 = Connector(
    inputs=["cells.#ids"],
    outputs=["growth.#ids"]
)

conn_gfp = Connector(
    inputs=["repressilator.gfp"],
    outputs=["cells.gfp"]
)

voronoi_marker = (model, tessellation,
    cell) -> begin
    #return :+
    verts = get_polygon_coordinates(tessellation, cell.index)
    return Makie.Polygon([Point2f(getxy(q) .- cell.pos) for q in verts])
end
function voronoi_color(cell)
    get(cgrad([:black, :green]), cell.gfp / cell.size^3 / (use_improved ? 10000.0 : 1000.0))
end
tessellation = voronoi(agents.triangulation; clip=true)
fig,
ax = abmplot(agents, agent_marker=cell -> voronoi_marker(agents, tessellation, cell),
    agent_color=voronoi_color,
    agentsplotkwargs=(strokewidth=1,), figure=(; size=(1600, 800), fontsize=34),
    axis=(; width=800, height=800), heatarray=:nutrients, heatkwargs=(colorrange=(
        0.0, 1.0),)
)
abmplot!(ax, agents; agent_marker=:xcross, agent_color=:red,
    agent_size=cell -> cell.id ∈ [1, 2] ? 10 : 0)
t = [0.0]
gfp1 = [let v = agents[1].gfp / agents[1].size^3;
    v > 0 ? v : NaN
end]
gfp2 = [let v = agents[2].gfp / agents[2].size^3;
    v > 0 ? v : NaN
end]
nut1 = [agents[1].nuts]
nut2 = [agents[2].nuts]
size1 = [agents[1].size^3]
size2 = [agents[2].size^3]
plot_layout = fig[:, end+1] = GridLayout()
gfp1_layout = plot_layout[1, 1] = GridLayout()
ax_1 = Axis(gfp1_layout[1, 1], title="Cell 1", xlabel="Time (Generations)",
    ylabel="GFP", width=600, height=400, yscale=log10, limits=(
        0, max_t, 1, 1e6))
ax_1_2 = Axis(gfp1_layout[1, 1],
    ylabel=rich(rich("Size", color=:blue), "/", rich("Nutrients", color=:green)),
    yaxisposition=:right)
lines!(ax_1, t, gfp1, color=:black, label="Total", linewidth=3)
lines!(ax_1_2, t, size1, color=:blue, label="Size", linewidth=3)
lines!(ax_1_2, t, nut1, color=:green, label="Nutrients", linewidth=3)
vlines!(ax_1, 0.0, color=:grey, linestyle=:dash, linewidth=3)
Makie.xlims!(ax_1_2, 0, max_t)
Makie.ylims!(ax_1_2, 0, 5.0)
gfp2_layout = plot_layout[2, 1] = GridLayout()
ax_2 = Axis(gfp2_layout[1, 1], title="Cell 2", xlabel="Time (Generations)",
    ylabel="GFP", width=600, height=400, yscale=log10, limits=(
        0, max_t, 1, 1e6))
ax_2_2 = Axis(gfp2_layout[1, 1],
    ylabel=rich(rich("Size", color=:blue), "/", rich("Nutrients", color=:green)),
    yaxisposition=:right)
lines!(ax_2, t, gfp2, color=:black, label="Total", linewidth=3)
lines!(ax_2_2, t, size2, color=:blue, label="Size", linewidth=3)
lines!(ax_2_2, t, nut2, color=:green, label="Nutrients", linewidth=3)
vlines!(ax_2, 0.0, color=:grey, linestyle=:dash, linewidth=3)
Makie.xlims!(ax_2_2, 0, max_t)
Makie.ylims!(ax_2_2, 0, 5.0)
resize_to_layout!(fig)
io = VideoStream(fig; framerate=20)
function plot_input(model)
    push!(t, abmtime(model) * model.dt)
    push!(gfp1, let v = model[1].gfp / model[1].size^3;
        v > 0 ? v : 1e-100
    end)
    push!(gfp2, let v = model[2].gfp / model[2].size^3;
        v > 0 ? v : 1e-100
    end)
    push!(nut1, model[1].nuts)
    push!(nut2, model[2].nuts)
    push!(size1, model[1].size^3)
    push!(size2, model[2].size^3)
    empty!(ax)
    empty!(ax_1)
    empty!(ax_2)
    empty!(ax_1_2)
    empty!(ax_2_2)
    tessellation = voronoi(model.triangulation; clip=true)
    abmplot!(ax, model; agent_marker=cell -> voronoi_marker(model, tessellation, cell),
        agent_color=voronoi_color,
        agentsplotkwargs=(strokewidth=1,), heatarray=:nutrients, heatkwargs=(colorrange=(
            0.0, 1.0),)
    )
    abmplot!(ax, model; agent_marker=:circle, agent_color=:red,
        agent_size=cell -> cell.id ∈ [1, 2] ? 10 : 0)
    lines!(ax_1, t, gfp1, color=:black, label="Total", linewidth=3)
    lines!(ax_1_2, t, size1, color=:blue, label="Size", linewidth=3)
    lines!(ax_1_2, t, nut1, color=:green, label="Nutrients", linewidth=3)
    vlines!(ax_1, t[end], color=:grey, linestyle=:dash, linewidth=3)
    lines!(ax_2, t, gfp2, color=:black, label="Total", linewidth=3)
    lines!(ax_2_2, t, size2, color=:blue, label="Size", linewidth=3)
    lines!(ax_2_2, t, nut2, color=:green, label="Nutrients", linewidth=3)
    vlines!(ax_2, t[end], color=:grey, linestyle=:dash, linewidth=3)
    recordframe!(io)
    @show abmtime(model) * model.dt
    @show nagents(model)
end

function set_initial_states!(states, ids, model)
    # init_states is returned, states is mutated
    init_states = Dict{Int,Vector{Float64}}()
    for id in allids(model)
        if id ∉ ids
            # New cell, so either divided or freshly created at start of simulation
            parent = model[id].parent
            if !isnothing(parent)
                states[ids .== parent.id] = states[ids .== parent.id] ./ 2
                init_states[id] = first(deepcopy(states[ids .== parent.id]))
            end
        end
    end
    return init_states
end

conn_init_states_rep = Connector(
    inputs=["repressilator.#states", "repressilator.#ids", "cells.#model"],
    outputs=["repressilator.#init_states"],
    func=set_initial_states!
)

conn_init_states_growth = Connector(
    inputs=["growth.#states", "growth.#ids", "cells.#model"],
    outputs=["growth.#init_states"],
    func=set_initial_states!
)

conn_gr = Connector(
    inputs=["growth.λ"],
    outputs=["repressilator.growth_rate"]
)

conn_size = Connector(
    inputs=["growth.mass"],
    outputs=["cells.size"],
    func=(M) -> (M ./ 1e8) .^ (1 / 3)
)

conn_volume = Connector(
    inputs=["growth.mass"],
    outputs=["repressilator.volume"],
    func=(V) -> (V ./ 1e8)
)

conn_nuts = Connector(
    inputs=["cells.nutrients"],
    outputs=["growth.s"],
    func=(nutrients) -> nutrients .* 1e4
)

conn_nuts_imp = Connector(
    inputs=["growth.import"],
    outputs=["cells.nut_import_rate"],
    func=(imp) -> imp ./ 1e8 * 1.5 # Scaling is arbitrary
)

function pde_to_agent(int)
    # Get just the nutrients from the state
    nuts = spat_getu(int, :nut, dsrs)
    #return ones(9,9)
    return reshape(clamp.(nuts, 1e-6, 1), (100, 100))
end

function agent_to_pde(nutrients, int)
    spat_setu!(int, :nut_rate, dsrs, nutrients)
    return reshape(nutrients, 100^2)
end

conn_nutrients_space = Connector(
    inputs=["PDE.#integrator"],
    outputs=["cells.space_nutrients"],
    func=pde_to_agent
)

conn_nut_import_rate_space = Connector(
    inputs=["cells.nut_import_rate_space", "PDE.#integrator"],
    outputs=String[],
    func=agent_to_pde
)

if use_improved
    sp = SirenProblem(
        components=[dup_g, dup_i, abm, pde], # TODO get awkward error when repressilator is run before growth
        connectors=[
            conn_init_states_rep, conn_init_states_growth, conn_ids_1, conn_ids_2, conn_gfp,
            conn_gr, conn_size, conn_nuts, conn_volume, conn_nuts_imp,
            conn_nutrients_space, conn_nut_import_rate_space],
        tspan=(0, max_t)
    )
else
    sp = SirenProblem(
        components=[dup_g, dup_r, abm, pde], # TODO get awkward error when repressilator is run before growth
        connectors=[
            conn_init_states_rep, conn_init_states_growth, conn_ids_1, conn_ids_2, conn_gfp,
            conn_gr, conn_size, conn_nuts, conn_volume, conn_nuts_imp,
            conn_nutrients_space, conn_nut_import_rate_space],
        tspan=(0, max_t)
    )
end

alg = MinimumTimeStepper()
start_time = time()
@profview sol = solve(sp, alg; save_vars=["cells.#model"], saveat=0.1)
end_time = time()
println("Simulation took $(end_time - start_time) seconds")

for model in sol["cells.#model"]
    plot_input(model)
end

if use_improved
    save("examples/outputs/repressilator_imp.mp4", io)
else
    save("examples/outputs/repressilator.mp4", io)
end
