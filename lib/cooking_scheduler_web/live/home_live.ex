defmodule CookingSchedulerWeb.HomeLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Duration, Kitchen, Meals}
  alias CookingScheduler.Kitchen.Appliance

  @impl true
  def mount(_params, _session, socket) do
    case Kitchen.list_appliances() do
      # Nothing set up yet: this is a first visit, so start with setup.
      [] ->
        {:ok, push_navigate(socket, to: ~p"/setup")}

      appliances ->
        {:ok,
         socket
         |> assign(:page_title, "Home")
         |> assign(:ovens, Enum.filter(appliances, &(&1.kind == :oven)))
         |> assign(:others, Enum.filter(appliances, &(&1.kind == :other)))
         |> assign(:ring_counts, Kitchen.ring_counts())
         |> load_meals()}
    end
  end

  defp load_meals(socket) do
    socket
    |> assign(:meals, Meals.list_meal_summaries())
    |> assign(:saved, Meals.list_saved_dishes())
    |> assign(:usage, Meals.usage_by_saved_dish())
  end

  @impl true
  def handle_event("new_meal", %{"from" => from}, socket) do
    {:ok, meal} =
      case from do
        "" -> Meals.create_meal()
        id -> id |> Meals.get_meal!() |> Meals.create_meal_from()
      end

    {:noreply, push_navigate(socket, to: ~p"/meals/#{meal.id}/plan")}
  end

  def handle_event("delete_meal", %{"id" => id}, socket) do
    {:ok, _} = id |> Meals.get_meal!() |> Meals.delete_meal()
    {:noreply, load_meals(socket)}
  end

  def handle_event("delete_dish", %{"id" => id}, socket) do
    {:ok, _} = id |> Meals.get_saved_dish!() |> Meals.delete_saved_dish()
    {:noreply, load_meals(socket)}
  end

  defp date_label(date), do: Calendar.strftime(date, "%d %b %Y")

  defp method_icon(:oven), do: "hero-fire"
  defp method_icon(:ring), do: "hero-stop-circle"
  defp method_icon(:appliance), do: "hero-bolt"

  defp ring_total(counts), do: counts |> Map.values() |> Enum.sum()

  defp ring_px(:small), do: "size-6"
  defp ring_px(:medium), do: "size-8"
  defp ring_px(:large), do: "size-10"

  # Position/width (in %) of an oven's range on a bar spanning its whole scale.
  defp bar_style(%Appliance{} = o) do
    top = Appliance.scale_top(o.temp_unit)
    left = (o.min_temp || 0) / top * 100
    width = max((o.max_temp - (o.min_temp || 0)) / top * 100, 4)
    "left: #{Float.round(left, 1)}%; width: #{Float.round(min(width, 100 - left), 1)}%"
  end

  attr :value, :integer, required: true
  attr :label, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div>
      <div class="text-4xl font-extrabold tabular-nums sm:text-5xl">{@value}</div>
      <div class="mt-1 text-sm font-medium uppercase tracking-wider text-primary-content/70">
        {@label}
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <div class={[
      "pop-in rounded-3xl border border-base-300 bg-base-100/90 p-6 shadow-sm backdrop-blur transition hover:-translate-y-0.5 hover:shadow-lg",
      @class
    ]}>
      <h2 class="flex items-center gap-2 text-sm font-semibold uppercase tracking-wider text-base-content/50">
        <.icon name={@icon} class="size-4" /> {@title}
      </h2>
      <div class="mt-4">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :delay, :integer, default: nil

  defp status_badge(assigns) do
    ~H"""
    <span :if={@status == :planned} class="badge badge-ghost badge-sm">Planned</span>
    <span :if={@status == :cooking} class="badge badge-warning badge-soft badge-sm">Cooking</span>
    <span :if={@status == :cooked and @delay == 0} class="badge badge-success badge-soft badge-sm">
      Cooked · on time
    </span>
    <span :if={@status == :cooked and @delay > 0} class="badge badge-warning badge-soft badge-sm">
      Cooked · {Duration.format(@delay)} late
    </span>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="pop-in relative overflow-hidden rounded-[2rem] bg-gradient-to-br from-primary via-primary to-secondary p-8 text-primary-content shadow-xl shadow-primary/20 sm:p-10">
        <div class="float-slow pointer-events-none absolute -right-10 -top-10 size-56 rounded-full border-[28px] border-white/10">
        </div>
        <div class="float-slow pointer-events-none absolute -bottom-16 right-24 size-40 rounded-full bg-white/10 [animation-delay:-3s]">
        </div>

        <div class="relative flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-4xl font-extrabold tracking-tight sm:text-5xl">Your kitchen</h1>
            <p class="mt-3 max-w-md text-primary-content/80">
              Plan a meal and we'll work out what goes where, and when.
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <.link
              id="create-dish"
              navigate={~p"/dishes/new"}
              class="btn rounded-full border-0 bg-white text-primary shadow-lg hover:bg-white/90"
            >
              <.icon name="hero-plus" class="size-4" /> Create dish
            </.link>
            <.link
              id="edit-kitchen"
              navigate={~p"/setup"}
              class="btn rounded-full border-0 bg-white/20 text-primary-content backdrop-blur hover:bg-white/30"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit kitchen
            </.link>
          </div>
        </div>

        <div class="relative mt-8 flex gap-10 border-t border-white/20 pt-6">
          <.stat value={length(@ovens)} label={if length(@ovens) == 1, do: "Oven", else: "Ovens"} />
          <.stat value={ring_total(@ring_counts)} label="Hob rings" />
          <.stat value={length(@others)} label="Other" />
        </div>
      </div>

      <section id="meals" class="mt-10">
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">Meals</h2>
          <form id="new-meal-form" phx-submit="new_meal" class="flex flex-wrap items-center gap-2">
            <select
              id="new-meal-from"
              name="from"
              aria-label="Start from"
              class="select select-sm rounded-full"
            >
              <option value="">Start from scratch</option>
              <option :for={%{meal: m} <- @meals} value={m.id}>
                Start from {m.name} ({date_label(m.date)})
              </option>
            </select>
            <button id="create-meal" type="submit" class="btn btn-sm btn-primary rounded-full">
              <.icon name="hero-plus" class="size-4" /> Create meal
            </button>
          </form>
        </div>

        <p
          :if={@meals == []}
          class="rounded-3xl border border-dashed border-base-300 p-8 text-center text-sm text-base-content/60"
        >
          No meals yet. Create one to start planning.
        </p>

        <ul :if={@meals != []} class="grid gap-3 sm:grid-cols-2">
          <li
            :for={s <- @meals}
            id={"meal-#{s.meal.id}"}
            class="pop-in rounded-3xl border border-base-300 bg-base-100/90 p-5 shadow-sm backdrop-blur transition hover:shadow-lg"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h3 class="truncate text-lg font-semibold">{s.meal.name}</h3>
                <p class="mt-0.5 text-sm text-base-content/60">
                  {date_label(s.meal.date)} · dinner at {Calendar.strftime(s.meal.serve_at, "%H:%M")}
                </p>
              </div>
              <button
                class="btn btn-xs btn-circle btn-ghost hover:text-error"
                phx-click="delete_meal"
                phx-value-id={s.meal.id}
                data-confirm={"Delete #{s.meal.name} and its #{s.dishes} dishes? This can't be undone."}
                aria-label={"Delete #{s.meal.name}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
            <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-base-content/70">
              <span>{s.dishes} {if s.dishes == 1, do: "dish", else: "dishes"}</span>
              <span :if={s.prep_minutes > 0}>{Duration.format(s.prep_minutes)} prep</span>
              <.status_badge status={s.status} delay={s.delay} />
            </div>
            <div class="mt-4 flex flex-wrap gap-2">
              <.link
                id={"plan-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/plan"}
                class="btn btn-sm rounded-full"
              >
                <.icon name="hero-table-cells" class="size-4" /> Plan
              </.link>
              <.link
                id={"cook-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/cook"}
                class="btn btn-sm btn-primary rounded-full"
              >
                <.icon name="hero-play" class="size-4" /> Cook
              </.link>
            </div>
          </li>
        </ul>
      </section>

      <section id="dishes" class="mt-10">
        <div class="mb-4 flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">Dishes</h2>
          <.link navigate={~p"/dishes/new"} class="btn btn-sm rounded-full">
            <.icon name="hero-plus" class="size-4" /> Create dish
          </.link>
        </div>

        <p
          :if={@saved == []}
          class="rounded-3xl border border-dashed border-base-300 p-8 text-center text-sm text-base-content/60"
        >
          No dishes yet. Create one, or add dishes while planning a meal.
        </p>

        <ul :if={@saved != []} class="grid gap-2">
          <li
            :for={d <- @saved}
            id={"dish-#{d.id}"}
            class="flex items-center gap-3 rounded-2xl border border-base-300 bg-base-100/90 px-4 py-3"
          >
            <span class="grid size-8 shrink-0 place-items-center rounded-lg bg-base-200 text-base-content/70">
              <.icon name={method_icon(d.method)} class="size-4" />
            </span>
            <div class="min-w-0 flex-1">
              <div class="truncate font-semibold">{d.name}</div>
              <div class="text-sm text-base-content/60">
                cook {Duration.format(d.cook_minutes + d.buffer_minutes)} · used in {length(
                  Map.get(@usage, d.id, [])
                )} {if length(Map.get(@usage, d.id, [])) == 1, do: "meal", else: "meals"}
              </div>
            </div>
            <.link
              navigate={~p"/dishes/#{d.id}/edit"}
              class="btn btn-xs btn-circle btn-ghost"
              aria-label={"Edit #{d.name}"}
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.link>
            <button
              class="btn btn-xs btn-circle btn-ghost hover:text-error"
              phx-click="delete_dish"
              phx-value-id={d.id}
              data-confirm={"Delete #{d.name}? Meals that already use it keep their copy."}
              aria-label={"Delete #{d.name}"}
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </li>
        </ul>
      </section>

      <div id="summary" class="mt-10 grid gap-4 sm:grid-cols-3">
        <.card icon="hero-fire" title="Ovens" class="[animation-delay:80ms]">
          <p :if={@ovens == []} class="text-sm text-base-content/50">None</p>
          <ul class="space-y-5">
            <li :for={o <- @ovens}>
              <div class="font-semibold">{o.name}</div>
              <div class="relative mt-2 h-2 rounded-full bg-base-200">
                <div
                  class="absolute h-2 rounded-full bg-gradient-to-r from-accent to-primary"
                  style={bar_style(o)}
                >
                </div>
              </div>
              <div class="mt-1.5 text-sm text-base-content/60">{Appliance.temp_range_label(o)}</div>
            </li>
          </ul>
        </.card>

        <.card icon="hero-stop-circle" title="Hob rings" class="[animation-delay:160ms]">
          <p :if={ring_total(@ring_counts) == 0} class="text-sm text-base-content/50">None</p>
          <ul class="space-y-3">
            <li
              :for={size <- Appliance.ring_sizes()}
              :if={@ring_counts[size] > 0}
              class="flex items-center gap-3"
            >
              <span class="flex min-w-24 flex-wrap gap-1.5">
                <span
                  :for={_ <- 1..@ring_counts[size]}
                  class={[
                    ring_px(size),
                    "shrink-0 rounded-full border-4 border-secondary/70 bg-secondary/5"
                  ]}
                ></span>
              </span>
              <span class="text-sm">
                <span class="font-semibold">{@ring_counts[size]}</span>
                <span class="text-base-content/60">{size}</span>
              </span>
            </li>
          </ul>
        </.card>

        <.card icon="hero-bolt" title="Other" class="[animation-delay:240ms]">
          <p :if={@others == []} class="text-sm text-base-content/50">None</p>
          <ul class="flex flex-wrap gap-2">
            <li :for={a <- @others} class="badge badge-lg badge-soft badge-accent">{a.name}</li>
          </ul>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
