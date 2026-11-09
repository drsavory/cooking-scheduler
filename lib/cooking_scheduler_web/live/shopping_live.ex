defmodule CookingSchedulerWeb.ShoppingLive do
  @moduledoc """
  A meal's shopping list, to tick off while shopping. Grouped by aisle, with cupboard staples
  set aside to check rather than buy (ADR 0021). Shareable as plain text.
  """
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.Meals
  alias CookingScheduler.Meals.{DishIngredient, Ingredient}

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
    items = Meals.shopping_list(meal)
    {staples, shop} = Enum.split_with(items, & &1.ingredient.staple)
    {bought, to_buy} = Enum.split_with(shop, & &1.bought?)

    aisles =
      to_buy
      |> Enum.group_by(& &1.ingredient.category)
      |> Enum.sort_by(fn {cat, _} -> Meals.category_order(cat) end)
      |> Enum.map(fn {cat, rows} ->
        %{category: cat, label: Ingredient.category_label(cat), rows: rows}
      end)

    socket
    |> assign(:page_title, "Shopping · #{meal.name}")
    |> assign(:meal, meal)
    |> assign(:items, items)
    |> assign(:aisles, aisles)
    |> assign(:staples, staples)
    |> assign(:bought, bought)
    |> assign(:shop_count, length(shop))
    |> assign(:share_text, Meals.shopping_list_text(meal))
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

  def handle_event("file_ingredient", %{"ingredient_id" => id, "ingredient" => attrs}, socket) do
    case Enum.find(socket.assigns.items, &(Integer.to_string(&1.ingredient.id) == id)) do
      nil ->
        {:noreply, socket}

      item ->
        with(
          {:ok, _} <- Meals.update_ingredient(item.ingredient, attrs),
          do: {:noreply, load(socket)}
        )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        navigate={~p"/meals/#{@meal.id}/prep"}
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> Prep
      </.link>

      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 class="text-3xl font-extrabold tracking-tight">Shopping list</h1>
          <p class="mt-1 text-sm text-base-content/60">{@meal.name}</p>
        </div>
        <button
          :if={@items != []}
          id="share-shopping"
          type="button"
          phx-hook=".ShareText"
          phx-update="ignore"
          data-title={"Shopping for #{@meal.name}"}
          data-text={@share_text}
          class="btn btn-sm btn-glass rounded-full"
        >
          <.icon name="hero-arrow-up-on-square" class="size-4" />
          <span data-label>Share list</span>
        </button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".ShareText">
          export default {
            mounted() {
              this.el.addEventListener("click", async () => {
                const text = this.el.dataset.text
                const title = this.el.dataset.title
                const label = this.el.querySelector("[data-label]")
                try {
                  if(navigator.share){
                    await navigator.share({title, text})
                  } else {
                    await navigator.clipboard.writeText(text)
                    label.textContent = "Copied"
                    setTimeout(() => label.textContent = "Share list", 1500)
                  }
                } catch(_e) { /* cancelled */ }
              })
            }
          }
        </script>
      </div>

      <p :if={@items == []} id="no-shopping" class="mt-6 text-base-content/60">
        No ingredients yet. Add them from each dish's details.
      </p>

      <div :if={@items != []}>
        <div id="shopping-progress" class="mt-5">
          <div class="mb-1 flex justify-between text-sm font-medium">
            <span>{length(@bought)} of {@shop_count} bought</span>
            <span :if={@aisles == [] and @shop_count > 0} class="text-success">All done</span>
          </div>
          <progress
            class="progress progress-success w-full"
            value={length(@bought)}
            max={max(@shop_count, 1)}
          ></progress>
        </div>

        <section :for={aisle <- @aisles} id={"aisle-#{aisle.category || "none"}"} class="mt-6">
          <h2 class="mb-2 flex items-center gap-2 text-sm font-semibold uppercase tracking-wider text-base-content/60">
            {aisle.label}
            <span
              :if={is_nil(aisle.category)}
              class="normal-case tracking-normal text-xs font-normal text-base-content/50"
            >
              · tap <.icon name="hero-tag-micro" class="inline size-3" /> to file by aisle
            </span>
          </h2>
          <ul id={"to-buy-#{aisle.category || "none"}"} class="grid gap-2">
            <li :for={row <- aisle.rows} id={"shopping-#{row.ingredient.id}"}>
              <.row row={row} />
            </li>
          </ul>
        </section>

        <section :if={@staples != []} id="cupboard" class="mt-8">
          <button
            type="button"
            class="flex w-full items-center justify-between text-sm font-semibold uppercase tracking-wider text-base-content/60"
            phx-click={JS.toggle(to: "#cupboard-list")}
          >
            <span>Check the cupboard ({length(@staples)})</span>
            <.icon name="hero-chevron-down-micro" class="size-4" />
          </button>
          <ul id="cupboard-list" style="display: none" class="mt-2 grid gap-2">
            <li :for={row <- @staples} id={"shopping-#{row.ingredient.id}"}>
              <.row row={row} />
            </li>
          </ul>
        </section>

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
    <div class={[
      "rounded-2xl border p-3 transition",
      @row.bought? && "border-success/40 bg-success/10",
      !@row.bought? && "border-base-300 bg-base-100/80 hover:border-primary/50 hover:shadow-md"
    ]}>
      <div class="flex items-center gap-3">
        <button
          id={"tick-shopping-#{@row.ingredient.id}"}
          type="button"
          role="checkbox"
          aria-checked={to_string(@row.bought?)}
          aria-label={"#{@row.ingredient.name} bought"}
          phx-click="toggle"
          phx-value-id={@row.ingredient.id}
          class="group flex min-w-0 flex-1 items-center gap-3 text-left"
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
        <.ingredient_filing ingredient={@row.ingredient} id={"file-#{@row.ingredient.id}"} />
      </div>
      <.ingredient_filing_form ingredient={@row.ingredient} id={"file-#{@row.ingredient.id}"} />
    </div>
    """
  end
end
