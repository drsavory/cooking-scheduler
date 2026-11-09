defmodule CookingSchedulerWeb.ShoppingLive do
  @moduledoc "A meal's shopping list, to tick off while shopping."
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.Meals
  alias CookingScheduler.Meals.DishIngredient

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(id)
    if connected?(socket), do: Meals.subscribe(meal)
    {:ok, load(socket, meal)}
  end

  defp load(socket), do: load(socket, Meals.get_meal!(socket.assigns.meal.id))

  @impl true
  def handle_info({:meal_updated, _id}, socket), do: {:noreply, load(socket)}

  defp load(socket, meal) do
    socket
    |> assign(:page_title, "Shopping · #{meal.name}")
    |> assign(:meal, meal)
    |> assign(:items, Meals.shopping_list(meal))
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)
    item = Enum.find(socket.assigns.items, &(&1.ingredient.id == id))

    if item, do: Meals.set_bought(socket.assigns.meal, id, !item.bought?)
    {:noreply, load(socket)}
  end

  def handle_event("clear", _params, socket) do
    :ok = Meals.clear_bought(socket.assigns.meal)
    {:noreply, load(socket)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:to_buy, Enum.reject(assigns.items, & &1.bought?))
      |> assign(:bought, Enum.filter(assigns.items, & &1.bought?))

    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        navigate={~p"/meals/#{@meal.id}/prep"}
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> Prep
      </.link>

      <h1 class="text-3xl font-extrabold tracking-tight">Shopping list</h1>
      <p class="mt-1 text-sm text-base-content/60">{@meal.name}</p>

      <p :if={@items == []} id="no-shopping" class="mt-6 text-base-content/60">
        No ingredients yet. Add them from each dish's details.
      </p>

      <div :if={@items != []}>
        <div id="shopping-progress" class="mt-5">
          <div class="mb-1 flex justify-between text-sm font-medium">
            <span>{length(@bought)} of {length(@items)} bought</span>
            <span :if={@to_buy == []} class="text-success">All done</span>
          </div>
          <progress
            class="progress progress-success w-full"
            value={length(@bought)}
            max={length(@items)}
          ></progress>
        </div>

        <ul id="to-buy" class="mt-5 grid gap-2">
          <li :for={row <- @to_buy} id={"shopping-#{row.ingredient.id}"}>
            <.row row={row} />
          </li>
        </ul>

        <div :if={@bought != []} class="mt-8">
          <div class="mb-2 flex items-center justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
              Bought
            </h2>
            <button id="clear-bought" class="btn btn-xs btn-ghost rounded-full" phx-click="clear">
              Untick all
            </button>
          </div>
          <ul id="bought" class="grid gap-2">
            <li :for={row <- @bought} id={"shopping-#{row.ingredient.id}"}>
              <.row row={row} />
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :row, :map, required: true

  defp row(assigns) do
    ~H"""
    <button
      id={"tick-shopping-#{@row.ingredient.id}"}
      type="button"
      role="checkbox"
      aria-checked={to_string(@row.bought?)}
      aria-label={"#{@row.ingredient.name} bought"}
      phx-click="toggle"
      phx-value-id={@row.ingredient.id}
      class={[
        "group flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition",
        @row.bought? && "border-success/40 bg-success/10",
        !@row.bought? && "border-base-300 bg-base-100/80 hover:border-primary/50 hover:shadow-md"
      ]}
    >
      <span class={[
        "grid size-7 shrink-0 place-items-center rounded-full border-2 transition",
        @row.bought? && "border-success bg-success text-success-content",
        !@row.bought? && "border-base-content/30 group-hover:border-primary"
      ]}>
        <.icon :if={@row.bought?} name="hero-check-micro" class="size-4" />
      </span>
      <span class="min-w-0 flex-1">
        <span class={["font-medium", @row.bought? && "line-through opacity-60"]}>
          {@row.ingredient.name}
        </span>
        <span class="block text-xs text-base-content/50">{Enum.join(@row.dishes, ", ")}</span>
      </span>
      <span class="shrink-0 text-right font-semibold tabular-nums">
        {Enum.map_join(@row.amounts, " + ", &DishIngredient.format_amount/1)}
      </span>
    </button>
    """
  end
end
