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
    saved = Meals.list_dishes()

    socket
    |> assign(:meals, Meals.list_meal_summaries())
    |> assign(:saved, saved)
    |> assign(:tags, saved |> Enum.flat_map(& &1.tags) |> Enum.frequencies() |> Enum.sort())
    |> assign_new(:tag, fn -> nil end)
    |> assign(:usage, Meals.usage_by_dish())
  end

  @impl true
  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    # Tapping the active tag again clears the filter.
    tag = if tag in ["", socket.assigns.tag], do: nil, else: tag
    {:noreply, assign(socket, :tag, tag)}
  end

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

  def handle_event("finish_meal", %{"id" => id}, socket) do
    {:ok, _} = id |> Meals.get_meal!() |> Meals.finish_meal()
    {:noreply, load_meals(socket)}
  end

  def handle_event("start_prepping", %{"id" => id}, socket) do
    meal = Meals.get_meal!(id)
    {:ok, _} = Meals.set_prep_status(meal, :prepping)
    {:noreply, push_navigate(socket, to: ~p"/meals/#{meal.id}/prep")}
  end

  def handle_event("set_meal_status", %{"id" => id, "status" => status}, socket)
      when status in ["planning", "prepping"] do
    {:ok, _} = id |> Meals.get_meal!() |> Meals.set_prep_status(String.to_existing_atom(status))
    {:noreply, load_meals(socket)}
  end

  def handle_event("reset_meal", %{"id" => id}, socket) do
    :ok = id |> Meals.get_meal!() |> Meals.reset_cooking()
    {:noreply, load_meals(socket)}
  end

  def handle_event("delete_meal_dish", %{"id" => id}, socket) do
    {:ok, _} = id |> Meals.get_dish!() |> Meals.delete_dish()
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
        {:planning, _} -> {"Planning", "text-base-content/70 bg-base-content/10"}
        {:prepping, _} -> {"Prepping", "text-info-content bg-info"}
        {:cooking, _} -> {"Cooking now", "text-warning-content bg-warning"}
        {:complete, 0} -> {"Complete · on time", "text-success-content bg-success"}
        {:complete, d} -> {"#{Duration.format(d)} late", "text-warning-content bg-warning"}
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

  defp visible(saved, nil), do: saved
  defp visible(saved, tag), do: Enum.filter(saved, &(tag in &1.tags))

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown, visible(assigns.saved, assigns.tag))

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
              <.confirm_button
                id={"delete-meal-#{s.meal.id}"}
                title={"Delete #{s.meal.name}?"}
                message={"This removes the meal and its #{plural(s.dishes, "dish", "dishes")}. This can't be undone."}
                confirm_label="Delete"
                tone={:danger}
                on_confirm={JS.push("delete_meal", value: %{id: s.meal.id})}
                class="btn btn-xs btn-circle btn-ghost opacity-0 transition group-hover:opacity-100 [@media(hover:none)]:opacity-100 hover:text-error focus:opacity-100"
                aria-label={"Delete #{s.meal.name}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </.confirm_button>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <.chip icon="hero-squares-2x2-micro" value={plural(s.dishes, "dish", "dishes")} />
              <.chip
                :if={s.prep_minutes > 0}
                icon="hero-clock-micro"
                value={"#{Duration.format(s.prep_minutes)} prep"}
              />
            </div>

            <div :if={s.status in [:planning, :prepping]} class="mt-4 flex gap-2 text-sm">
              <button
                :if={s.status == :planning}
                id={"start-prepping-#{s.meal.id}"}
                phx-click={JS.push("start_prepping", value: %{id: s.meal.id})}
                class="btn btn-xs btn-ghost rounded-full"
              >
                <.icon name="hero-shopping-bag-micro" class="size-3.5" /> Start prepping
              </button>
              <.link
                :if={s.status == :prepping}
                id={"prep-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/prep"}
                class="btn btn-xs btn-primary btn-soft rounded-full"
              >
                <.icon name="hero-clipboard-document-check-micro" class="size-3.5" /> Open prep
              </.link>
              <button
                :if={s.status == :prepping}
                id={"back-to-planning-#{s.meal.id}"}
                phx-click={JS.push("set_meal_status", value: %{id: s.meal.id, status: "planning"})}
                class="btn btn-xs btn-ghost rounded-full"
              >
                <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> Back to planning
              </button>
            </div>

            <div :if={s.status in [:cooking, :complete]} class="mt-4 flex gap-2 text-sm">
              <.confirm_button
                :if={s.status == :cooking}
                id={"finish-meal-#{s.meal.id}"}
                title="Finish cooking now?"
                message="Dishes that aren't done yet are left out of the result."
                confirm_label="Finish"
                on_confirm={JS.push("finish_meal", value: %{id: s.meal.id})}
                class="btn btn-xs btn-ghost rounded-full"
              >
                <.icon name="hero-flag-micro" class="size-3.5" /> Finish cooking
              </.confirm_button>
              <.confirm_button
                id={"reset-meal-#{s.meal.id}"}
                title="Reset cooking progress?"
                message="Started and finished marks are cleared. The plan stays."
                confirm_label="Reset"
                tone={:danger}
                on_confirm={JS.push("reset_meal", value: %{id: s.meal.id})}
                class="btn btn-xs btn-ghost rounded-full"
              >
                <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> Reset progress
              </.confirm_button>
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

        <div :if={@tags != []} id="tag-filter" class="mb-4 flex flex-wrap gap-2">
          <button
            type="button"
            id="tag-all"
            phx-click="filter_tag"
            phx-value-tag=""
            class={[
              "rounded-full border px-3 py-1 text-sm transition",
              (@tag == nil && "border-primary bg-primary/15 font-semibold text-primary") ||
                "border-base-300 hover:border-primary/50"
            ]}
          >
            All
          </button>
          <button
            :for={{tag, count} <- @tags}
            type="button"
            id={"tag-filter-#{tag}"}
            phx-click="filter_tag"
            phx-value-tag={tag}
            aria-pressed={to_string(@tag == tag)}
            class={[
              "rounded-full border px-3 py-1 text-sm capitalize transition",
              (@tag == tag && "border-primary bg-primary/15 font-semibold text-primary") ||
                "border-base-300 hover:border-primary/50"
            ]}
          >
            {tag} <span class="text-xs opacity-60">{count}</span>
          </button>
        </div>

        <ul :if={@saved != []} class="grid gap-3 sm:grid-cols-2">
          <li
            :for={{d, i} <- Enum.with_index(@shown)}
            id={"dish-#{d.id}"}
            style={stagger(i)}
            class="glass glass-lift pop-in group relative flex items-center gap-3 rounded-2xl p-3 pr-2"
          >
            <span class={[
              "grid size-11 shrink-0 place-items-center rounded-xl bg-gradient-to-br text-white shadow-md",
              method_gradient(d.method)
            ]}>
              <.icon name={method_icon(d.method)} class="size-5" />
            </span>
            <div class="min-w-0 flex-1">
              <.link
                id={"view-dish-#{d.id}"}
                navigate={~p"/dishes/#{d.id}"}
                class="block truncate font-semibold hover:text-primary after:absolute after:inset-0"
              >
                {d.name}
              </.link>
              <div class="text-xs text-base-content/60">
                {Duration.format(d.cook_minutes + d.buffer_minutes)} cook · {plural(
                  length(Map.get(@usage, d.id, [])),
                  "meal",
                  "meals"
                )}
              </div>
              <div :if={d.tags != []} id={"dish-tags-#{d.id}"} class="mt-1 flex flex-wrap gap-1">
                <span
                  :for={tag <- d.tags}
                  class="rounded-full bg-base-content/10 px-2 py-0.5 text-[11px] capitalize"
                >
                  {tag}
                </span>
              </div>
            </div>
            <.confirm_button
              id={"delete-dish-#{d.id}"}
              title={"Delete #{d.name}?"}
              message="Meals that already use it keep their copy."
              confirm_label="Delete"
              tone={:danger}
              on_confirm={JS.push("delete_meal_dish", value: %{id: d.id})}
              class="relative z-10 btn btn-xs btn-circle btn-ghost opacity-0 transition group-hover:opacity-100 [@media(hover:none)]:opacity-100 hover:text-error focus:opacity-100"
              aria-label={"Delete #{d.name}"}
            >
              <.icon name="hero-trash" class="size-4" />
            </.confirm_button>
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
