defmodule CookingSchedulerWeb.PrepLive do
  @moduledoc "Everything to do before the cooking day: get the ingredients in, then prep ahead."
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Dates, Duration, Kitchen, Meals, Planner}
  alias CookingScheduler.Meals.{DishIngredient, Meal, MealDish}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(id)
    if connected?(socket), do: Meals.subscribe(meal)
    {:ok, load(socket, meal)}
  end

  @impl true
  def handle_info({:meal_updated, _id}, socket), do: {:noreply, load(socket)}

  defp load(socket), do: load(socket, Meals.get_meal!(socket.assigns.meal.id))

  defp load(socket, %Meal{} = meal) do
    dishes = Meals.list_meal_dishes(meal)
    entries = Planner.plan(dishes, Meal.serve_minutes(meal), Kitchen.list_appliances())

    ingredients =
      Map.new(dishes, fn d -> {d.id, Meals.list_dish_ingredients(d)} end)

    shopping = Meals.shopping_list(meal)

    socket
    |> assign(:shopping, Enum.reject(shopping, & &1.ingredient.staple))
    |> assign(
      :bought,
      for(
        row <- shopping,
        row.bought? or row.ingredient.staple,
        into: MapSet.new(),
        do: row.ingredient.id
      )
    )
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
    dish = Meals.get_meal_dish!(id)
    {:ok, _} = Meals.set_ingredients_in(dish, !dish.ingredients_in)
    {:noreply, load(socket)}
  end

  def handle_event("toggle_prepped", %{"id" => id}, socket) do
    dish = Meals.get_meal_dish!(id)
    {:ok, _} = Meals.set_prepped(dish, !dish.prepped)
    {:noreply, load(socket)}
  end

  def handle_event("all_ingredients_in", _params, socket) do
    :ok = Meals.set_all_ingredients_in(socket.assigns.meal, true)
    {:noreply, load(socket)}
  end

  defp prep_entries(entries), do: Enum.filter(entries, &(&1.dish.prep_minutes > 0))

  # Prep-ahead dishes grouped by when they're meant to be done (ADR 0022), soonest-needed first.
  defp prep_groups(entries) do
    labels = %{
      day_before: {"The day before", "Get these done ahead."},
      morning_of: {"The morning of", "First thing on the day."},
      before_cooking:
        {"Just before cooking",
         "These are on the cook screen too; tick them here if you get ahead."}
    }

    for day <- MealDish.prep_days(),
        rows = Enum.filter(prep_entries(entries), &(&1.dish.prep_day == day)),
        rows != [] do
      {title, hint} = labels[day]
      %{day: day, title: title, hint: hint, entries: rows}
    end
  end

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
  attr :meal_dish_id, :integer, required: true
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
      phx-value-id={@meal_dish_id}
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

    assigns =
      assign(assigns,
        done: done,
        total: total,
        prep: prep_entries(assigns.entries),
        prep_groups: prep_groups(assigns.entries)
      )

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
        <span
          id="prep-countdown"
          class="ml-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary"
        >
          {Dates.relative(@meal.date)}
        </span>
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

        <.link
          id="shopping-link"
          navigate={~p"/meals/#{@meal.id}/shopping"}
          class="mt-8 flex items-center justify-between gap-3 rounded-2xl border border-base-300 bg-base-100/80 p-4 transition hover:border-primary/50 hover:shadow-md"
        >
          <span>
            <span class="flex items-center gap-2 font-semibold">
              <.icon name="hero-shopping-cart" class="size-5" /> Shopping list
            </span>
            <span id="shopping-summary" class="block text-sm text-base-content/60">
              <%= if @shopping == [] do %>
                No ingredients yet
              <% else %>
                {Enum.count(@shopping, & &1.bought?)} of {length(@shopping)} bought
              <% end %>
            </span>
          </span>
          <.icon name="hero-chevron-right" class="size-5 text-base-content/40" />
        </.link>

        <section id="ingredients-section" class="mt-8">
          <div class="mb-3 flex items-center justify-between gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
              1. Check the ingredients are in
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
                meal_dish_id={e.dish.id}
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
                  id={"ingredient-status-#{e.dish.id}"}
                  class="mt-1.5 flex flex-wrap gap-1.5"
                >
                  <span
                    :for={di <- Map.fetch!(@ingredients, e.dish.id)}
                    id={"dish-#{e.dish.id}-ingredient-#{di.ingredient.id}"}
                    data-state={
                      if MapSet.member?(@bought, di.ingredient.id), do: "in", else: "missing"
                    }
                    class={[
                      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium",
                      MapSet.member?(@bought, di.ingredient.id) && "bg-success/15 text-success",
                      !MapSet.member?(@bought, di.ingredient.id) &&
                        "bg-warning/20 text-warning-content"
                    ]}
                  >
                    <.icon
                      name={
                        if MapSet.member?(@bought, di.ingredient.id),
                          do: "hero-check-micro",
                          else: "hero-shopping-cart-micro"
                      }
                      class="size-3"
                    />
                    {ingredient_label(di)}
                  </span>
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
          <div :for={group <- @prep_groups} id={"prep-#{group.day}"} class="mb-5">
            <h3 class="mb-1 text-sm font-semibold">{group.title}</h3>
            <p class="mb-2 text-xs text-base-content/60">{group.hint}</p>
            <ul class="grid gap-2">
              <li :for={e <- group.entries} id={"prep-#{e.dish.id}"}>
                <.tick
                  id={"tick-prepped-#{e.dish.id}"}
                  done={e.dish.prepped}
                  label={"#{e.dish.name} prepped"}
                  event="toggle_prepped"
                  meal_dish_id={e.dish.id}
                >
                  <span class="font-semibold">{e.dish.name}</span>
                  <span class="block text-sm text-base-content/60">
                    {Duration.format(e.dish.prep_minutes)} prep<span :if={
                      e.dish.notes not in [nil, ""]
                    }> · {e.dish.notes}</span>
                  </span>
                </.tick>
              </li>
            </ul>
          </div>
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
