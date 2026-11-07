defmodule CookingSchedulerWeb.HomeLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Duration, Kitchen, Meals}

  @impl true
  def mount(_params, _session, socket) do
    case Kitchen.list_appliances() do
      # Nothing set up yet: this is a first visit, so start with setup.
      [] ->
        {:ok, push_navigate(socket, to: ~p"/setup")}

      _appliances ->
        {:ok,
         socket
         |> assign(:page_title, "Home")
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

  defp method_gradient(:oven), do: "from-orange-400 to-rose-500"
  defp method_gradient(:ring), do: "from-emerald-400 to-teal-500"
  defp method_gradient(:appliance), do: "from-amber-300 to-yellow-500"

  defp stagger(i), do: "animation-delay: #{min(i, 12) * 45}ms"

  defp plural(1, one, _many), do: "1 #{one}"
  defp plural(n, _one, many), do: "#{n} #{many}"

  attr :status, :atom, required: true
  attr :delay, :integer, default: nil

  defp status_pill(assigns) do
    {label, tone} =
      case {assigns.status, assigns.delay} do
        {:planned, _} -> {"Planned", "text-base-content/70 bg-base-content/10"}
        {:cooking, _} -> {"Cooking now", "text-warning-content bg-warning"}
        {:cooked, 0} -> {"On time", "text-success-content bg-success"}
        {:cooked, d} -> {"#{Duration.format(d)} late", "text-warning-content bg-warning"}
      end

    assigns = assign(assigns, label: label, tone: tone)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold",
      @tone
    ]}>
      <span class={["size-1.5 rounded-full bg-current", @status == :cooking && "dot-live"]}></span>
      {@label}
    </span>
    """
  end

  attr :date, Date, required: true

  defp date_tile(assigns) do
    ~H"""
    <div class="grid size-16 shrink-0 place-items-center rounded-2xl bg-gradient-to-br from-primary to-accent text-primary-content shadow-lg shadow-primary/25">
      <div class="text-center leading-none">
        <div class="text-[10px] font-bold uppercase tracking-widest opacity-80">
          {Calendar.strftime(@date, "%b")}
        </div>
        <div class="mt-1 text-2xl font-extrabold tabular-nums">{@date.day}</div>
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :value, :any, required: true

  defp chip(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded-full bg-base-content/5 px-2.5 py-1 text-xs font-medium text-base-content/70">
      <.icon name={@icon} class="size-3.5" /> {@value}
    </span>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="pop-in">
        <p class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/50">
          Cooking scheduler
        </p>
        <h1 class="mt-2 text-5xl font-extrabold tracking-tight sm:text-6xl">
          What are we <span class="gradient-text">cooking</span>?
        </h1>

        <form
          id="new-meal-form"
          phx-submit="new_meal"
          class="glass mt-6 flex flex-wrap items-center gap-3 rounded-[1.75rem] p-3"
        >
          <div class="relative min-w-0 flex-1 basis-64">
            <.icon
              name="hero-document-duplicate"
              class="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-base-content/50"
            />
            <select
              id="new-meal-from"
              name="from"
              aria-label="Start from"
              class="select h-12 w-full rounded-full border-0 bg-base-200 pl-11 text-base text-base-content"
            >
              <option value="" class="bg-base-100 text-base-content">Start from scratch</option>
              <option :for={%{meal: m} <- @meals} value={m.id} class="bg-base-100 text-base-content">
                Start from {m.name} ({date_label(m.date)})
              </option>
            </select>
          </div>
          <button id="create-meal" type="submit" class="btn btn-glow h-12 rounded-full px-6 text-base">
            <.icon name="hero-sparkles" class="size-5" /> Create meal
          </button>
          <.link
            id="create-dish"
            navigate={~p"/dishes/new"}
            class="btn btn-glass h-12 rounded-full px-5 text-base"
          >
            <.icon name="hero-plus" class="size-5" /> Create dish
          </.link>
        </form>
      </section>

      <section id="meals" class="mt-12">
        <h2 class="mb-4 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          Meals
          <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@meals)}</span>
        </h2>

        <p
          :if={@meals == []}
          class="glass rounded-3xl border-dashed p-10 text-center text-base-content/60"
        >
          <.icon name="hero-cake" class="mx-auto mb-2 size-8 opacity-60" />
          No meals yet. Create one above to start planning.
        </p>

        <ul :if={@meals != []} class="grid gap-4 sm:grid-cols-2">
          <li
            :for={{s, i} <- Enum.with_index(@meals)}
            id={"meal-#{s.meal.id}"}
            style={stagger(i)}
            class="glass glass-lift pop-in group flex flex-col rounded-[1.75rem] p-5"
          >
            <div class="flex items-start gap-4">
              <.date_tile date={s.meal.date} />
              <div class="min-w-0 flex-1">
                <h3 class="truncate text-xl font-bold tracking-tight">{s.meal.name}</h3>
                <p class="mt-0.5 text-sm text-base-content/60">
                  Dinner at {Calendar.strftime(s.meal.serve_at, "%H:%M")}
                </p>
                <div class="mt-2"><.status_pill status={s.status} delay={s.delay} /></div>
              </div>
              <button
                class="btn btn-xs btn-circle btn-ghost opacity-0 transition group-hover:opacity-100 [@media(hover:none)]:opacity-100 hover:text-error focus:opacity-100"
                phx-click="delete_meal"
                phx-value-id={s.meal.id}
                data-confirm={"Delete #{s.meal.name} and its #{s.dishes} dishes? This can't be undone."}
                aria-label={"Delete #{s.meal.name}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <.chip icon="hero-squares-2x2-micro" value={plural(s.dishes, "dish", "dishes")} />
              <.chip
                :if={s.prep_minutes > 0}
                icon="hero-clock-micro"
                value={"#{Duration.format(s.prep_minutes)} prep"}
              />
            </div>

            <div class="mt-5 flex gap-2">
              <.link
                id={"plan-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/plan"}
                class="btn btn-glass flex-1 rounded-full"
              >
                <.icon name="hero-table-cells" class="size-4" /> Plan
              </.link>
              <.link
                id={"cook-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/cook"}
                class="btn btn-glow flex-1 rounded-full"
              >
                <.icon name="hero-play-solid" class="size-4" /> Cook
              </.link>
            </div>
          </li>
        </ul>
      </section>

      <section id="dishes" class="mt-12">
        <h2 class="mb-4 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          Dishes
          <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@saved)}</span>
        </h2>

        <p
          :if={@saved == []}
          class="glass rounded-3xl border-dashed p-10 text-center text-base-content/60"
        >
          <.icon name="hero-beaker" class="mx-auto mb-2 size-8 opacity-60" />
          No dishes yet. Create one, or add dishes while planning a meal.
        </p>

        <ul :if={@saved != []} class="grid gap-3 sm:grid-cols-2">
          <li
            :for={{d, i} <- Enum.with_index(@saved)}
            id={"dish-#{d.id}"}
            style={stagger(i)}
            class="glass glass-lift pop-in group flex items-center gap-3 rounded-2xl p-3 pr-2"
          >
            <span class={[
              "grid size-11 shrink-0 place-items-center rounded-xl bg-gradient-to-br text-white shadow-md",
              method_gradient(d.method)
            ]}>
              <.icon name={method_icon(d.method)} class="size-5" />
            </span>
            <div class="min-w-0 flex-1">
              <div class="truncate font-semibold">{d.name}</div>
              <div class="text-xs text-base-content/60">
                {Duration.format(d.cook_minutes + d.buffer_minutes)} cook · {plural(
                  length(Map.get(@usage, d.id, [])),
                  "meal",
                  "meals"
                )}
              </div>
            </div>
            <.link
              navigate={~p"/dishes/#{d.id}/edit"}
              class="btn btn-xs btn-circle btn-ghost opacity-0 transition group-hover:opacity-100 [@media(hover:none)]:opacity-100 focus:opacity-100"
              aria-label={"Edit #{d.name}"}
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.link>
            <button
              class="btn btn-xs btn-circle btn-ghost opacity-0 transition group-hover:opacity-100 [@media(hover:none)]:opacity-100 hover:text-error focus:opacity-100"
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

      <p class="mt-14 text-center text-sm text-base-content/50">
        <.link id="edit-kitchen" navigate={~p"/setup"} class="link link-hover">
          <.icon name="hero-cog-6-tooth-micro" class="size-4" /> Kitchen settings
        </.link>
      </p>
    </Layouts.app>
    """
  end
end
