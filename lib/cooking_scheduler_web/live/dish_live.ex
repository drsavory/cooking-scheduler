defmodule CookingSchedulerWeb.DishLive do
  @moduledoc """
  One dish: its cooking details, notes, link and ingredients. The boxes are read-only until
  you press Edit, then change in place (same layout) and only save on Save. Works for a dish in a meal (`:meal`) and for a
  library dish (`:saved`).
  """
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Dates, Duration, Kitchen, Meals, Photos, RecipeImport, RecipeLink}
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.{MealDish, DishIngredient, Dish}

  @impl true
  def mount(%{"meal_id" => meal_id, "id" => id} = params, _session, socket) do
    meal = Meals.get_meal!(meal_id)
    dish = Meals.get_meal_dish!(id)

    if dish.meal_id != meal.id, do: raise(Ecto.NoResultsError, queryable: MealDish)

    back =
      if params["from"] == "cook",
        do: {~p"/meals/#{meal.id}/cook", "Back to cooking"},
        else: {~p"/meals/#{meal.id}/plan", "Back to #{meal.name}"}

    {:ok,
     socket
     |> assign(:kitchen, Kitchen.list_appliances())
     |> setup(dish, back, meal.name)}
  end

  def mount(%{"id" => id}, _session, socket) do
    dish = Meals.get_dish!(id)

    {:ok, socket |> assign(:kitchen, []) |> setup(dish, {~p"/", "All dishes"}, nil)}
  end

  defp setup(socket, dish, back, meal_name) do
    socket
    |> assign(:back, back)
    |> assign(:meal_name, meal_name)
    |> assign(:error, nil)
    |> assign(:editing, false)
    |> assign(:importing, false)
    |> assign(:photos, Photos.list_for(dish))
    |> assign(:history, if(match?(%Dish{}, dish), do: Meals.dish_history(dish), else: []))
    |> assign_dish(dish)
    |> load_ingredients()
  end

  defp assign_dish(socket, dish) do
    socket
    |> assign(:page_title, dish.name)
    |> assign(:dish, dish)
    |> assign(:dish_form, to_form(change(dish, %{}), as: :dish))
  end

  defp change(%MealDish{} = dish, attrs), do: Meals.change_meal_dish(dish, attrs)
  defp change(%Dish{} = dish, attrs), do: Meals.change_dish(dish, attrs)

  defp update_meal_dish(%MealDish{} = dish, attrs), do: Meals.update_meal_dish(dish, attrs)
  defp update_meal_dish(%Dish{} = dish, attrs), do: Meals.update_dish(dish, attrs)

  defp reload(%MealDish{id: id}), do: Meals.get_meal_dish!(id)
  defp reload(%Dish{id: id}), do: Meals.get_dish!(id)

  defp load_ingredients(socket) do
    socket
    |> assign(:ingredients, Meals.list_dish_ingredients(socket.assigns.dish))
    |> assign(:known, Meals.list_ingredients())
    |> assign(:form, to_form(%{"name" => "", "amount" => "", "unit" => ""}, as: :ingredient))
    |> assign(:paste_form, to_form(%{"text" => ""}, as: :paste))
  end

  @impl true
  def handle_event("edit", _params, socket), do: {:noreply, assign(socket, :editing, true)}

  # Throw away unsaved changes.
  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> assign(:editing, false) |> assign_dish(reload(socket.assigns.dish))}
  end

  # Typing only checks the values; nothing is saved until Save.
  def handle_event("validate", %{"dish" => params}, %{assigns: %{editing: true}} = socket) do
    form = socket.assigns.dish |> change(params) |> to_form(action: :validate, as: :dish)
    {:noreply, assign(socket, :dish_form, form)}
  end

  def handle_event("save", %{"dish" => params}, %{assigns: %{editing: true}} = socket) do
    dish = socket.assigns.dish

    case update_meal_dish(dish, params) do
      {:ok, _} ->
        {:noreply, socket |> assign(:editing, false) |> assign_dish(reload(dish))}

      {:error, changeset} ->
        {:noreply, assign(socket, :dish_form, to_form(changeset, action: :validate, as: :dish))}
    end
  end

  # Enter in a locked box, or a stale event after cancelling.
  def handle_event(event, _params, socket) when event in ["validate", "save"],
    do: {:noreply, socket}

  def handle_event("add_ingredient", %{"ingredient" => %{"name" => name} = params}, socket) do
    case Meals.add_ingredient(socket.assigns.dish, name, params["amount"], params["unit"]) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:error, nil)
         |> load_ingredients()
         |> push_event("focus", %{id: "ingredient_name"})}

      {:error, :name} ->
        {:noreply,
         socket
         |> assign(:error, "Give the ingredient a name")
         |> push_event("focus", %{id: "ingredient_name"})}

      {:error, :amount} ->
        {:noreply, assign(socket, :error, "Amount should be a number, like 50, 1.5 or 1/2")}
    end
  end

  def handle_event("remove_ingredient", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.ingredients, &(Integer.to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      di ->
        {:ok, _} = Meals.remove_ingredient(socket.assigns.dish, di)
        {:noreply, load_ingredients(socket)}
    end
  end

  # A whole list at once (ADR 0023): one ingredient per line.
  def handle_event("paste_ingredients", %{"paste" => %{"text" => text}}, socket) do
    %{added: added, skipped: skipped} = Meals.add_ingredients_from_text(socket.assigns.dish, text)

    socket =
      socket
      |> load_ingredients()
      |> assign(
        :error,
        if(skipped == [], do: nil, else: "Couldn't read: " <> Enum.join(skipped, "; "))
      )

    socket =
      if added == [],
        do: socket,
        else:
          put_flash(
            socket,
            :info,
            "Added #{length(added)} #{if length(added) == 1, do: "ingredient", else: "ingredients"}"
          )

    {:noreply, socket}
  end

  def handle_event("file_ingredient", %{"ingredient_id" => id, "ingredient" => attrs}, socket) do
    case Enum.find(socket.assigns.ingredients, &(Integer.to_string(&1.ingredient.id) == id)) do
      nil ->
        {:noreply, socket}

      di ->
        {:ok, _} = Meals.update_ingredient(di.ingredient, attrs)
        {:noreply, load_ingredients(socket)}
    end
  end

  # Pulls ingredients (and times, where the dish has none) from the recipe link (ADR 0023).
  def handle_event("import_recipe", _params, socket) do
    link = socket.assigns.dish.link

    {:noreply,
     socket
     |> assign(:importing, true)
     |> start_async(:import, fn -> RecipeImport.fetch(link) end)}
  end

  @impl true
  def handle_async(:import, {:ok, {:ok, recipe}}, socket) do
    dish = socket.assigns.dish
    %{added: added} = Meals.add_ingredients_from_text(dish, Enum.join(recipe.ingredients, "\n"))

    times =
      for {field, value} <- [prep_minutes: recipe.prep_minutes, cook_minutes: recipe.cook_minutes],
          value,
          Map.fetch!(dish, field) == 0,
          into: %{},
          do: {field, value}

    if times != %{}, do: {:ok, _} = update_meal_dish(dish, times)

    summary =
      ["#{length(added)} ingredients"] ++
        if(times == %{}, do: [], else: ["times from the recipe"])

    {:noreply,
     socket
     |> assign(:importing, false)
     |> assign_dish(reload(dish))
     |> load_ingredients()
     |> put_flash(
       :info,
       "Imported " <> Enum.join(summary, " and ") <> " from #{RecipeLink.host(dish.link)}"
     )}
  end

  def handle_async(:import, {:ok, {:error, reason}}, socket) do
    message =
      case reason do
        :no_recipe -> "That page doesn't have a recipe we can read."
        :bad_link -> "That doesn't look like a web address."
        _ -> "Couldn't reach that page."
      end

    {:noreply, socket |> assign(:importing, false) |> put_flash(:error, message)}
  end

  def handle_async(:import, {:exit, _}, socket),
    do:
      {:noreply,
       socket |> assign(:importing, false) |> put_flash(:error, "Couldn't read that page.")}

  # ---- display helpers ------------------------------------------------------

  defp lateness_label(nil), do: "not finished"
  defp lateness_label(0), do: "on time"
  defp lateness_label(m) when m > 0, do: "#{Duration.format(m)} late"
  defp lateness_label(m), do: "#{Duration.format(-m)} early"

  defp serve_options(current) do
    presets = MealDish.serve_offset_options()

    if current in [nil | Enum.map(presets, &elem(&1, 1))],
      do: presets,
      else: presets ++ [{"Custom · #{current}m", current}]
  end

  defp method_label(:oven), do: "Oven"
  defp method_label(:ring), do: "Hob"
  defp method_label(:appliance), do: "Slow cooker / grill"

  defp oven_options(kitchen),
    do: [{"Choose for me", ""} | for(o <- kitchen, o.kind == :oven, do: {o.name, o.id})]

  defp appliance_options(kitchen),
    do: [{"Choose…", ""} | for(a <- kitchen, a.kind == :other, do: {a.name, a.id})]

  defp meal_dish?(%MealDish{}), do: true
  defp meal_dish?(_), do: false

  defp field_value(v) when is_integer(v), do: Duration.format(v)

  defp field_value(v) when is_atom(v) and not is_nil(v) and not is_boolean(v),
    do: Atom.to_string(v)

  defp field_value(v), do: v

  attr :f, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :options, :list, default: []
  attr :class, :string, default: nil
  attr :locked, :boolean, default: false
  attr :rest, :global, include: ~w(placeholder step min rows)

  # One editable box: a small label over a borderless input.
  defp box(assigns) do
    ~H"""
    <label class={[
      "block min-w-0 rounded-xl bg-base-content/5 px-3 py-1.5 transition",
      !@locked && "focus-within:bg-base-content/10 focus-within:ring-2 focus-within:ring-primary/40",
      @f.errors != [] && "ring-2 ring-error/50",
      @class
    ]}>
      <span class="block text-[10px] font-semibold uppercase tracking-wider text-base-content/50">
        {@label}
      </span>
      <%= case @type do %>
        <% "select" -> %>
          <select
            id={@f.id}
            name={@f.name}
            disabled={@locked}
            class="-ml-1 w-full bg-transparent text-base font-bold outline-none enabled:cursor-pointer disabled:appearance-none disabled:opacity-100"
            {@rest}
          >
            {Phoenix.HTML.Form.options_for_select(@options, @f.value)}
          </select>
        <% "textarea" -> %>
          <textarea
            id={@f.id}
            name={@f.name}
            readonly={@locked}
            class="w-full resize-y bg-transparent text-sm outline-none"
            {@rest}
          >{Phoenix.HTML.Form.normalize_value("textarea", @f.value)}</textarea>
        <% _ -> %>
          <input
            type={@type}
            id={@f.id}
            name={@f.name}
            value={field_value(@f.value)}
            autocomplete="off"
            readonly={@locked}
            class="w-full bg-transparent text-base font-bold tabular-nums outline-none placeholder:font-normal placeholder:text-base-content/30"
            {@rest}
          />
      <% end %>
      <span :for={{msg, opts} <- @f.errors} class="mt-0.5 block text-xs leading-tight text-error">
        {translate_error({msg, opts})}
      </span>
    </label>
    """
  end

  @impl true
  def render(assigns) do
    {back_path, back_label} = assigns.back
    assigns = assign(assigns, back_path: back_path, back_label: back_label)

    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        id="dish-back"
        navigate={@back_path}
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> {@back_label}
      </.link>

      <div class="grid gap-x-8 gap-y-6 lg:grid-cols-[minmax(0,1fr)_minmax(22rem,42%)]">
        <div class="min-w-0">
          <.form for={@dish_form} id="dish-form" phx-change="validate" phx-submit="save">
            <header class="flex items-start justify-between gap-4">
              <div class="min-w-0 flex-1">
                <input
                  type="text"
                  id={@dish_form[:name].id}
                  name={@dish_form[:name].name}
                  value={@dish_form[:name].value}
                  aria-label="Dish name"
                  phx-debounce="400"
                  readonly={not @editing}
                  class={[
                    "input -ml-3 h-auto w-full px-3 py-1 text-3xl font-extrabold tracking-tight",
                    (@editing && "input-bordered") || "input-ghost pointer-events-none",
                    @dish_form[:name].errors != [] && "input-error"
                  ]}
                />
                <p class="mt-1 text-sm text-base-content/60">
                  {if meal_dish?(@dish), do: "In #{@meal_name}", else: "Saved dish"} · {method_label(
                    @dish.method
                  )}
                </p>
              </div>
              <div class="flex shrink-0 gap-2">
                <%= if @editing do %>
                  <button
                    type="button"
                    id="cancel-edit"
                    phx-click="cancel"
                    class="btn btn-ghost rounded-full"
                  >
                    Cancel
                  </button>
                  <button id="save-dish" type="submit" class="btn btn-primary rounded-full">
                    <.icon name="hero-check" class="size-4" /> Save
                  </button>
                <% else %>
                  <button
                    type="button"
                    id="edit-dish"
                    phx-click="edit"
                    class="btn btn-glass rounded-full"
                  >
                    <.icon name="hero-pencil-square" class="size-4" /> Edit
                  </button>
                <% end %>
              </div>
            </header>

            <section :if={not meal_dish?(@dish)} id="dish-tags" class="mt-4">
              <h2 class="mb-2 text-sm font-semibold uppercase tracking-wider text-base-content/60">
                Tags
              </h2>
              <.tag_picker
                field={@dish_form[:tags]}
                custom={@dish_form[:custom_tags]}
                suggested={Dish.suggested_tags()}
                locked={not @editing}
              />
            </section>

            <section id="dish-details" class="mt-4">
              <h2 class="mb-2 text-sm font-semibold uppercase tracking-wider text-base-content/60">
                Cooking
              </h2>
              <div class="grid grid-cols-[repeat(auto-fill,minmax(7.5rem,1fr))] gap-2">
                <%= if @dish.method == :oven do %>
                  <.box
                    locked={not @editing}
                    f={@dish_form[:temp]}
                    label="Temperature"
                    type="number"
                    step="any"
                    phx-debounce="500"
                  />
                  <.box
                    locked={not @editing}
                    f={@dish_form[:temp_unit]}
                    label="Scale"
                    type="select"
                    options={for u <- Appliance.temp_units(), do: {Appliance.temp_unit_label(u), u}}
                  />
                  <.box
                    locked={not @editing}
                    f={@dish_form[:oven_share]}
                    label="Oven space"
                    type="select"
                    options={CookingScheduler.Meals.MealDish.oven_share_options()}
                  />
                  <.box
                    :if={meal_dish?(@dish)}
                    locked={not @editing}
                    f={@dish_form[:appliance_id]}
                    label="Oven"
                    type="select"
                    class="col-span-2"
                    options={oven_options(@kitchen)}
                  />
                <% end %>
                <.box
                  :if={@dish.method == :ring}
                  locked={not @editing}
                  f={@dish_form[:ring_size]}
                  label="Ring"
                  type="select"
                  options={[{"Small", :small}, {"Medium", :medium}, {"Large", :large}]}
                />
                <.box
                  :if={@dish.method == :appliance and meal_dish?(@dish)}
                  locked={not @editing}
                  f={@dish_form[:appliance_id]}
                  label="Appliance"
                  type="select"
                  class="col-span-2"
                  options={appliance_options(@kitchen)}
                />
                <.box
                  locked={not @editing}
                  f={@dish_form[:prep_minutes]}
                  label="Prep"
                  placeholder="0m"
                  phx-debounce="400"
                />
                <.box
                  locked={not @editing}
                  f={@dish_form[:cook_minutes]}
                  label="Cook"
                  placeholder="1h 30m"
                  phx-debounce="400"
                />
                <.box
                  locked={not @editing}
                  f={@dish_form[:rest_minutes]}
                  label="Rest"
                  placeholder="0m"
                  phx-debounce="400"
                />
                <.box
                  locked={not @editing}
                  f={@dish_form[:serve_offset_minutes]}
                  label="Course"
                  type="select"
                  class="col-span-2"
                  options={serve_options(@dish.serve_offset_minutes)}
                />
                <.box
                  locked={not @editing}
                  f={@dish_form[:prep_day]}
                  label="Prep when"
                  type="select"
                  class="col-span-2"
                  options={MealDish.prep_day_options()}
                />
              </div>

              <div class="mt-2 grid gap-2 sm:grid-cols-2">
                <.box
                  locked={not @editing}
                  f={@dish_form[:notes]}
                  label="Notes"
                  type="textarea"
                  rows="2"
                  phx-debounce="400"
                />
                <div>
                  <.box
                    locked={not @editing}
                    f={@dish_form[:link]}
                    label="Recipe link"
                    placeholder="https://…"
                    phx-debounce="400"
                  />
                  <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1">
                    <a
                      :if={@dish.link not in [nil, ""]}
                      id="dish-link"
                      href={@dish.link}
                      target="_blank"
                      rel="noopener"
                      class="link link-hover inline-flex items-center gap-1 text-sm text-primary"
                    >
                      <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" /> Open recipe
                      <span
                        :if={RecipeLink.host(@dish.link)}
                        id="dish-link-host"
                        class="text-base-content/60"
                      >
                        on {RecipeLink.host(@dish.link)}
                      </span>
                    </a>
                    <button
                      :if={not @editing and RecipeLink.host(@dish.link)}
                      type="button"
                      id="import-recipe"
                      phx-click="import_recipe"
                      disabled={@importing}
                      class="btn btn-xs btn-primary btn-soft rounded-full"
                    >
                      <.icon
                        name={
                          if @importing,
                            do: "hero-arrow-path-micro",
                            else: "hero-arrow-down-tray-micro"
                        }
                        class={["size-3.5", @importing && "motion-safe:animate-spin"]}
                      />
                      {if @importing, do: "Reading the recipe…", else: "Import ingredients & times"}
                    </button>
                  </div>
                </div>
              </div>
            </section>
          </.form>

          <section
            :if={meal_dish?(@dish) and @dish.next_time not in [nil, ""]}
            id="dish-next-time"
            class="mt-6"
          >
            <h2 class="mb-2 text-sm font-semibold uppercase tracking-wider text-base-content/60">
              Next time
            </h2>
            <p class="whitespace-pre-line rounded-xl bg-accent/15 px-3 py-2 text-sm">
              {@dish.next_time}
            </p>
          </section>

          <section :if={not meal_dish?(@dish) and @history != []} id="dish-history" class="mt-6">
            <h2 class="mb-2 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
              How it went
              <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@history)}</span>
            </h2>
            <ul class="grid gap-2">
              <li
                :for={h <- @history}
                id={"history-#{h.meal_dish.id}"}
                class="glass rounded-xl px-3 py-2 text-sm"
              >
                <div class="flex flex-wrap items-baseline justify-between gap-x-3">
                  <.link
                    navigate={~p"/meals/#{h.meal.id}/summary"}
                    class="font-semibold hover:text-primary"
                  >
                    {h.meal.name}
                  </.link>
                  <span class="text-xs text-base-content/60">
                    {Calendar.strftime(h.meal.date, "%d %b %Y")} · {Dates.relative(h.meal.date)}
                  </span>
                </div>
                <div class="mt-0.5 flex flex-wrap gap-x-3 text-xs text-base-content/70">
                  <span>Planned {Duration.format(h.meal_dish.cook_minutes)}, took {Duration.format(
                    Meals.actual_cook(h.meal_dish)
                  )}</span>
                  <span class={[
                    h.lateness && h.lateness > 0 && "text-warning font-semibold",
                    h.lateness == 0 && "text-success"
                  ]}>
                    {lateness_label(h.lateness)}
                  </span>
                </div>
                <p
                  :if={h.meal_dish.next_time not in [nil, ""]}
                  class="mt-1 whitespace-pre-line rounded-lg bg-accent/15 px-2 py-1 text-xs"
                >
                  {h.meal_dish.next_time}
                </p>
              </li>
            </ul>
          </section>

          <section id="ingredients" class="mt-6">
            <h2 class="mb-3 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
              Ingredients
              <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">
                {length(@ingredients)}
              </span>
            </h2>

            <ul id="ingredient-list" class="grid gap-1.5">
              <li
                :for={di <- @ingredients}
                id={"ingredient-#{di.id}"}
                class="glass group rounded-xl px-3 py-1"
              >
                <div class="flex items-center gap-2">
                  <span class="min-w-0 flex-1 truncate font-medium">
                    {di.ingredient.name}
                    <span
                      :if={di.ingredient.staple}
                      class="ml-1 text-xs font-normal text-base-content/50"
                    >
                      cupboard
                    </span>
                  </span>
                  <span
                    :if={DishIngredient.format(di)}
                    id={"ingredient-amount-#{di.id}"}
                    class="text-sm tabular-nums text-base-content/60"
                  >
                    {DishIngredient.format(di)}
                  </span>
                  <.ingredient_filing ingredient={di.ingredient} id={"file-#{di.ingredient.id}"} />
                  <button
                    type="button"
                    id={"remove-ingredient-#{di.id}"}
                    class="btn btn-xs btn-circle btn-ghost hover:text-error"
                    phx-click="remove_ingredient"
                    phx-value-id={di.id}
                    aria-label={"Remove #{di.ingredient.name}"}
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
                <.ingredient_filing_form ingredient={di.ingredient} id={"file-#{di.ingredient.id}"} />
              </li>
            </ul>

            <p :if={@ingredients == []} id="no-ingredients" class="text-sm text-base-content/60">
              No ingredients yet.
            </p>

            <.form
              for={@form}
              id="ingredient-form"
              phx-submit="add_ingredient"
              class="mt-4 flex flex-wrap items-start gap-2"
            >
              <div class="min-w-48 flex-1">
                <.input
                  field={@form[:name]}
                  type="text"
                  list="known-ingredients"
                  placeholder="Ingredient, e.g. butter"
                  autocomplete="off"
                  aria-label="Ingredient"
                />
                <datalist id="known-ingredients">
                  <option :for={i <- @known} value={i.name}></option>
                </datalist>
              </div>
              <div class="w-28">
                <.input
                  field={@form[:amount]}
                  type="text"
                  inputmode="decimal"
                  placeholder="Amount"
                  aria-label="Amount"
                />
              </div>
              <div class="w-28">
                <.input
                  field={@form[:unit]}
                  type="select"
                  aria-label="Unit"
                  options={[
                    {"items", ""} | Enum.map(DishIngredient.units(), &{Atom.to_string(&1), &1})
                  ]}
                />
              </div>
              <button id="add-ingredient" class="btn btn-glow rounded-full">
                <.icon name="hero-plus" class="size-4" /> Add
              </button>
            </.form>
            <p :if={@error} id="ingredient-error" class="mt-1 text-sm text-error">{@error}</p>

            <details id="paste-ingredients" class="mt-4 group">
              <summary class="cursor-pointer text-sm text-base-content/60 hover:text-primary">
                <.icon name="hero-clipboard-document-micro" class="inline size-4" />
                Paste a list instead
              </summary>
              <.form for={@paste_form} id="paste-form" phx-submit="paste_ingredients" class="mt-2">
                <.input
                  field={@paste_form[:text]}
                  type="textarea"
                  rows="5"
                  placeholder="One per line, as a recipe writes it:\n200 g butter\n2 onions, chopped\n1 tbsp olive oil"
                  aria-label="Ingredient list"
                />
                <button id="paste-add" class="btn btn-sm btn-primary btn-soft rounded-full">
                  <.icon name="hero-plus-micro" class="size-4" /> Add them all
                </button>
              </.form>
            </details>
          </section>
        </div>

        <aside id="dish-photos" class="order-first lg:order-none lg:sticky lg:top-4 lg:self-start">
          <h2 class="mb-3 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
            Photos
            <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">
              {length(@photos)}
            </span>
          </h2>

          <ul
            :if={@photos != []}
            id="dish-photo-grid"
            class="grid grid-cols-2 gap-3"
          >
            <li
              :for={{{photo, meal}, i} <- Enum.with_index(@photos)}
              id={"dish-photo-#{photo.id}"}
              class={["group min-w-0", i == 0 && "col-span-2"]}
            >
              <a
                href={~p"/photos/#{photo.id}"}
                target="_blank"
                rel="noopener"
                class={[
                  "block overflow-hidden rounded-2xl bg-base-content/5 shadow-lg",
                  (i == 0 && "aspect-[4/3]") || "aspect-square"
                ]}
              >
                <img
                  src={~p"/photos/#{photo.id}"}
                  alt={"#{@dish.name} in #{meal.name}"}
                  loading="lazy"
                  class="size-full object-cover transition duration-300 group-hover:scale-105"
                />
              </a>
              <.link
                navigate={~p"/meals/#{meal.id}/summary"}
                id={"dish-photo-meal-#{photo.id}"}
                class="mt-1 block truncate text-sm text-base-content/70 hover:text-primary"
              >
                {meal.name} · {Calendar.strftime(meal.date, "%b %Y")}
              </.link>
            </li>
          </ul>

          <div
            :if={@photos == []}
            id="no-photos"
            class="flex aspect-[4/3] flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-base-content/20 p-6 text-center text-sm text-base-content/60"
          >
            <.icon name="hero-camera" class="size-8" />
            No photos yet. Add them from a meal's Photos page once it's finished.
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
