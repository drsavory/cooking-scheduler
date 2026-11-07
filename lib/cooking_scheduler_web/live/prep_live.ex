defmodule CookingSchedulerWeb.PrepLive do
  @moduledoc "Everything to do before the cooking day: get the ingredients in, then prep ahead."
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Duration, Kitchen, Meals, Planner}
  alias CookingScheduler.Meals.{DishIngredient, Meal}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, load(socket, Meals.get_meal!(id))}
  end

  defp load(socket), do: load(socket, Meals.get_meal!(socket.assigns.meal.id))

  defp load(socket, %Meal{} = meal) do
    dishes = Meals.list_dishes(meal)
    entries = Planner.plan(dishes, Meal.serve_minutes(meal), Kitchen.list_appliances())

    ingredients =
      Map.new(dishes, fn d -> {d.id, Meals.list_dish_ingredients(d)} end)

    socket
    |> assign(:page_title, "Prep · #{meal.name}")
    |> assign(:meal, meal)
    |> assign(:entries, Enum.sort_by(entries, & &1.dish.name))
    |> assign(:ingredients, ingredients)
  end

  @impl true
  def handle_event("start_prepping", _params, socket) do
    {:ok, _} = Meals.set_prep_status(socket.assigns.meal, :prepping)
    {:noreply, load(socket)}
  end

  def handle_event("toggle_ingredients", %{"id" => id}, socket) do
    dish = Meals.get_dish!(id)
    {:ok, _} = Meals.set_ingredients_in(dish, !dish.ingredients_in)
    {:noreply, load(socket)}
  end

  def handle_event("toggle_prepped", %{"id" => id}, socket) do
    dish = Meals.get_dish!(id)
    {:ok, _} = Meals.set_prepped(dish, !dish.prepped)
    {:noreply, load(socket)}
  end

  def handle_event("all_ingredients_in", _params, socket) do
    :ok = Meals.set_all_ingredients_in(socket.assigns.meal, true)
    {:noreply, load(socket)}
  end

  defp prep_entries(entries), do: Enum.filter(entries, &(&1.dish.prep_minutes > 0))

  defp progress(entries) do
    prep = prep_entries(entries)
    total = length(entries) + length(prep)
    done = Enum.count(entries, & &1.dish.ingredients_in) + Enum.count(prep, & &1.dish.prepped)
    {done, total}
  end

  attr :id, :string, required: true
  attr :done, :boolean, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :dish_id, :integer, required: true
  slot :inner_block, required: true

  defp tick(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="checkbox"
      aria-checked={to_string(@done)}
      aria-label={@label}
      phx-click={@event}
      phx-value-id={@dish_id}
      class={[
        "group flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition",
        @done && "border-success/40 bg-success/10",
        !@done && "border-base-300 bg-base-100/80 hover:border-primary/50 hover:shadow-md"
      ]}
    >
      <span class={[
        "grid size-7 shrink-0 place-items-center rounded-full border-2 transition",
        @done && "border-success bg-success text-success-content",
        !@done && "border-base-content/30 group-hover:border-primary"
      ]}>
        <.icon :if={@done} name="hero-check-micro" class="size-4" />
      </span>
      <span class="min-w-0 flex-1">{render_slot(@inner_block)}</span>
    </button>
    """
  end

  @impl true
  def render(assigns) do
    {done, total} = progress(assigns.entries)
    assigns = assign(assigns, done: done, total: total, prep: prep_entries(assigns.entries))

    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        navigate={~p"/"}
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> All meals
      </.link>

      <h1 class="text-3xl font-extrabold tracking-tight sm:text-4xl">{@meal.name}</h1>
      <p class="mt-1 text-sm text-base-content/60">
        {Calendar.strftime(@meal.date, "%A %d %B")} · dinner at {Calendar.strftime(
          @meal.serve_at,
          "%H:%M"
        )}
      </p>

      <div
        :if={@meal.status == :planning}
        id="not-prepping"
        class="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-info/10 p-4 text-sm"
      >
        <span>This meal is still being planned.</span>
        <button
          id="start-prepping"
          class="btn btn-sm btn-primary rounded-full"
          phx-click="start_prepping"
        >
          <.icon name="hero-shopping-bag-micro" class="size-4" /> Start prepping
        </button>
      </div>

      <div
        :if={@entries == []}
        id="no-dishes"
        class="mt-6 rounded-3xl border border-dashed border-base-300 p-8 text-center"
      >
        <p class="text-base-content/60">No dishes yet. Add some in the plan first.</p>
        <.link navigate={~p"/meals/#{@meal.id}/plan"} class="btn btn-primary mt-4 rounded-full">
          Go to plan
        </.link>
      </div>

      <div :if={@entries != []}>
        <div id="prep-progress" class="mt-5">
          <div class="mb-1 flex justify-between text-sm font-medium">
            <span>{@done} of {@total} done</span>
            <span :if={@done == @total} class="text-success">All ready</span>
          </div>
          <progress class="progress progress-success w-full" value={@done} max={@total}></progress>
        </div>

        <section id="ingredients-section" class="mt-8">
          <div class="mb-3 flex items-center justify-between gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
              1. Get the ingredients in
            </h2>
            <button
              id="all-ingredients-in"
              class="btn btn-xs btn-ghost rounded-full"
              phx-click="all_ingredients_in"
            >
              <.icon name="hero-check-micro" class="size-3.5" /> Everything's in
            </button>
          </div>
          <ul class="grid gap-2">
            <li :for={e <- @entries} id={"ingredients-#{e.dish.id}"}>
              <.tick
                id={"tick-ingredients-#{e.dish.id}"}
                done={e.dish.ingredients_in}
                label={"All ingredients in for #{e.dish.name}"}
                event="toggle_ingredients"
                dish_id={e.dish.id}
              >
                <span class="font-semibold">{e.dish.name}</span>
                <span
                  :if={Map.fetch!(@ingredients, e.dish.id) == []}
                  class="block text-sm text-base-content/50"
                >
                  No ingredients listed
                </span>
                <span
                  :if={Map.fetch!(@ingredients, e.dish.id) != []}
                  class="block text-sm text-base-content/60"
                >
                  {Enum.map_join(Map.fetch!(@ingredients, e.dish.id), ", ", &ingredient_label/1)}
                </span>
              </.tick>
            </li>
          </ul>
        </section>

        <section id="prep-section" class="mt-8">
          <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
            2. Prep ahead
          </h2>
          <p :if={@prep == []} id="no-prep" class="text-sm text-base-content/60">
            Nothing needs prepping before the day.
          </p>
          <ul class="grid gap-2">
            <li :for={e <- @prep} id={"prep-#{e.dish.id}"}>
              <.tick
                id={"tick-prepped-#{e.dish.id}"}
                done={e.dish.prepped}
                label={"#{e.dish.name} prepped"}
                event="toggle_prepped"
                dish_id={e.dish.id}
              >
                <span class="font-semibold">{e.dish.name}</span>
                <span class="block text-sm text-base-content/60">
                  {Duration.format(e.dish.prep_minutes)} prep<span :if={e.dish.notes not in [nil, ""]}> · {e.dish.notes}</span>
                </span>
              </.tick>
            </li>
          </ul>
        </section>

        <div class="mt-10 flex flex-wrap justify-end gap-2">
          <.link
            navigate={~p"/meals/#{@meal.id}/plan"}
            id="back-to-plan"
            class="btn btn-glass rounded-full"
          >
            <.icon name="hero-table-cells" class="size-4" /> Plan
          </.link>
          <.link navigate={~p"/meals/#{@meal.id}/cook"} id="go-cook" class="btn btn-glow rounded-full">
            <.icon name="hero-play-solid" class="size-4" /> Ready to cook
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp ingredient_label(di) do
    case DishIngredient.format(di) do
      nil -> di.ingredient.name
      amount -> "#{di.ingredient.name} (#{amount})"
    end
  end
end
