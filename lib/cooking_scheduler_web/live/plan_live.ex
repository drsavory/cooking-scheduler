defmodule CookingSchedulerWeb.PlanLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Duration, Kitchen, Meals, Planner}
  alias CookingScheduler.Meals.{MealDish, Meal}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(id)
    if connected?(socket), do: Meals.subscribe(meal)

    {:ok,
     socket
     |> assign(:invalid, %{})
     |> assign(:open, MapSet.new())
     |> assign(:adding, nil)
     |> assign(:sizing, nil)
     |> assign(:histories, %{})
     |> assign(:saved_query, "")
     |> assign(:from_meal, nil)
     |> assign(
       :other_meals,
       for(s <- Meals.list_meal_summaries(), s.meal.id != meal.id, s.dishes > 0, do: s.meal)
     )
     |> load(meal)}
  end

  defp load(socket), do: load(socket, Meals.get_meal!(socket.assigns.meal.id))

  defp load(socket, %Meal{} = meal) do
    kitchen = Kitchen.list_appliances()
    dishes = Meals.list_meal_dishes(meal)

    socket
    |> assign(:page_title, meal.name)
    |> assign(:kitchen, kitchen)
    |> assign(:meal, meal)
    |> assign(:meal_form, to_form(Meals.change_meal(meal), id: "meal"))
    |> assign_plan(dishes, Meal.serve_minutes(meal), kitchen)
    |> assign(:saved, Meals.dishes_not_in(meal))
  end

  defp assign_plan(socket, dishes, serve, kitchen) do
    entries = Planner.plan(dishes, serve, kitchen)

    # One suggestion list per dish that has a problem (ADR 0020).
    fixes =
      for e <- entries, e.issues != [], into: %{} do
        {e.dish.id, Planner.suggest(dishes, serve, kitchen, e.dish.id)}
      end

    socket
    |> assign(:entries, entries)
    |> assign(:sections, sections(entries))
    |> assign(:problems, Enum.filter(entries, &(&1.issues != [])))
    |> assign(:fixes, fixes)
    |> assign(:load, Planner.load(entries, kitchen))
    |> assign(:oven_events, Planner.oven_events(entries, kitchen))
    |> assign(:serve, Planner.last_serve(entries, serve))
  end

  # The plan reads like the day: rows in the order you start them, split into parts of the day
  # (ADR 0020). A dish with no cooking time can't be placed, so it goes last.
  defp sections(entries) do
    entries
    |> Enum.sort_by(&{&1.dish.cook_minutes == 0, start_of(&1), &1.cook_at, &1.dish.name})
    |> Enum.chunk_by(&day_part(start_of(&1), &1.dish.cook_minutes == 0))
    |> Enum.map(fn [first | _] = rows ->
      %{label: day_part(start_of(first), first.dish.cook_minutes == 0), entries: rows}
    end)
  end

  defp start_of(%{dish: %{prep_minutes: p, prep_day: :before_cooking}} = e) when p > 0,
    do: e.prep_at

  defp start_of(e), do: e.cook_at

  defp day_part(_at, true), do: "Needs a cooking time"
  defp day_part(at, _) when at < 0, do: "The day before"
  defp day_part(at, _) when at < 12 * 60, do: "Morning"
  defp day_part(at, _) when at < 17 * 60, do: "Afternoon"
  defp day_part(_at, _), do: "Evening"

  @impl true
  def handle_event("open_add", _params, socket) do
    tab = if socket.assigns.saved == [], do: :new, else: :pick

    # Past versions of each sized dish, for the picker (ADR 0029).
    histories =
      for d <- socket.assigns.saved,
          MealDish.sized?(d),
          into: %{},
          do: {d.id, Meals.dish_history(d)}

    {:noreply,
     socket
     |> assign(:adding, tab)
     |> assign(:sizing, nil)
     |> assign(:histories, histories)
     |> assign(:saved_query, "")}
  end

  def handle_event("close_add", _params, socket), do: {:noreply, assign(socket, :adding, nil)}

  # Picking a sized dish asks for its weight first, and which version to start from.
  def handle_event("size_saved", %{"id" => id}, socket) do
    dish = Meals.get_dish!(id)
    history = Map.get(socket.assigns.histories, dish.id, [])
    size = Meals.suggested_size(dish, history)

    {:noreply,
     assign(socket, :sizing, %{
       dish: dish,
       history: history,
       weight: if(size, do: MealDish.size_number(size), else: ""),
       from: ""
     })}
  end

  def handle_event("unsize", _params, socket), do: {:noreply, assign(socket, :sizing, nil)}

  def handle_event("size_change", %{"sizing" => params}, socket) do
    {:noreply,
     update(socket, :sizing, fn s ->
       %{s | weight: params["weight"] || s.weight, from: params["from"] || s.from}
     end)}
  end

  def handle_event("add_sized", %{"sizing" => params}, socket) do
    %{dish: dish, history: history} = socket.assigns.sizing
    from = Enum.find(history, &(to_string(&1.meal_dish.id) == params["from"]))

    case parse_size(params["weight"]) do
      {:ok, size} ->
        opts = [size: size, from: from && from.meal_dish]

        case Meals.add_dish_to_meal(socket.assigns.meal, dish, opts) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(adding: nil, sizing: nil)
             |> put_flash(:info, "#{dish.name} added")
             |> load()}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, "#{dish.name} can't be added as it is: check its details")}
        end

      :error ->
        {:noreply, update(socket, :sizing, &Map.put(&1, :weight, params["weight"] || ""))}
    end
  end

  def handle_event("add_tab", %{"tab" => "new"}, socket),
    do: {:noreply, assign(socket, :adding, :new)}

  def handle_event("add_tab", %{"tab" => "pick"}, socket),
    do: {:noreply, assign(socket, :adding, :pick)}

  def handle_event("add_tab", %{"tab" => "meal"}, socket),
    do: {:noreply, assign(socket, :adding, :meal)}

  def handle_event("pick_from_meal", %{"meal" => ""}, socket),
    do: {:noreply, assign(socket, :from_meal, nil)}

  def handle_event("pick_from_meal", %{"meal" => id}, socket) do
    meal = Meals.get_meal!(id)
    {:noreply, assign(socket, :from_meal, %{meal: meal, dishes: Meals.list_meal_dishes(meal)})}
  end

  def handle_event("add_from_meal", %{"id" => id}, socket) do
    dish = Meals.get_meal_dish!(id)

    case Meals.copy_meal_dish(dish, socket.assigns.meal) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "#{dish.name} added") |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "#{dish.name} couldn't be added")}
    end
  end

  # Rows are a one-line summary; tapping one opens its settings (ADR 0026).
  def handle_event("toggle_dish", %{"id" => id}, socket) do
    id = String.to_integer(id)

    open =
      if MapSet.member?(socket.assigns.open, id),
        do: MapSet.delete(socket.assigns.open, id),
        else: MapSet.put(socket.assigns.open, id)

    {:noreply, assign(socket, :open, open)}
  end

  # Clicking a dish on the Kitchen load jumps to its row and opens it (ADR 0028).
  def handle_event("show_dish", %{"id" => id}, socket) do
    {:noreply, update(socket, :open, &MapSet.put(&1, id))}
  end

  # A planner suggestion, applied to the dish (ADR 0020).
  def handle_event("apply_fix", %{"dish" => id, "index" => index}, socket) do
    id = String.to_integer(id)

    case socket.assigns.fixes |> Map.get(id, []) |> Enum.at(String.to_integer(index)) do
      nil ->
        {:noreply, socket}

      %{attrs: attrs, label: label} ->
        {:ok, _} = Meals.update_meal_dish(Meals.get_meal_dish!(id), attrs)
        {:noreply, socket |> put_flash(:info, "Done: #{String.downcase(label)}") |> load()}
    end
  end

  def handle_event("filter_saved", %{"q" => q}, socket),
    do: {:noreply, assign(socket, :saved_query, q)}

  def handle_event("start_from_last_year", _params, socket) do
    Meals.load_starter_dishes(socket.assigns.meal, socket.assigns.kitchen)
    {:noreply, load(socket)}
  end

  def handle_event("copy_from", %{"id" => id}, socket) do
    :ok = Meals.copy_meal_dishes(Meals.get_meal!(id), socket.assigns.meal)
    {:noreply, load(socket)}
  end

  def handle_event("add_saved", %{"id" => id}, socket) do
    dish = Meals.get_dish!(id)

    case Meals.add_dish_to_meal(socket.assigns.meal, dish) do
      {:ok, _} ->
        {:noreply,
         socket |> assign(:adding, nil) |> put_flash(:info, "#{dish.name} added") |> load()}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "#{dish.name} can't be added as it is: check its details")}
    end
  end

  def handle_event("start_prepping", _params, socket) do
    meal = socket.assigns.meal
    if meal.status == :planning, do: {:ok, _} = Meals.set_prep_status(meal, :prepping)
    {:noreply, push_navigate(socket, to: ~p"/meals/#{meal.id}/prep")}
  end

  def handle_event("copy_meal", _params, socket) do
    {:ok, meal} = Meals.create_meal_from(socket.assigns.meal)
    {:noreply, push_navigate(socket, to: ~p"/meals/#{meal.id}/plan")}
  end

  def handle_event("update_meal", %{"meal" => params}, socket) do
    case Meals.update_meal(socket.assigns.meal, params) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  # Cards are always-editable forms: every change is saved as soon as it's valid.
  def handle_event("update", %{"meal_dish_id" => id, "meal_dish" => params}, socket) do
    dish = Meals.get_meal_dish!(id)
    changeset = Meals.change_meal_dish(dish, params)

    if changeset.valid? do
      {:ok, _} = Meals.update_meal_dish(dish, params)
      {:noreply, socket |> update(:invalid, &Map.delete(&1, dish.id)) |> load()}
    else
      form = to_form(%{changeset | action: :validate}, id: form_id(dish))
      {:noreply, update(socket, :invalid, &Map.put(&1, dish.id, form))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    dish = Meals.get_meal_dish!(id)
    {:ok, _} = Meals.delete_meal_dish(dish)
    {:noreply, socket |> update(:invalid, &Map.delete(&1, dish.id)) |> load()}
  end

  # Something changed on another device or screen.
  @impl true
  def handle_info({:meal_updated, _id}, socket), do: {:noreply, load(socket)}

  def handle_info(:close_add_dish, socket), do: {:noreply, assign(socket, :adding, nil)}

  # A new sized dish isn't in the meal yet: it goes to the weight step (ADR 0029).
  def handle_info({:new_sized_dish, dish}, socket) do
    socket = socket |> load() |> assign(:adding, :pick) |> assign(:histories, %{})
    handle_event("size_saved", %{"id" => to_string(dish.id)}, socket)
  end

  def handle_info({:new_dish, dish, {:ok, _meal_dish}}, socket) do
    {:noreply, socket |> assign(:adding, nil) |> put_flash(:info, "#{dish.name} added") |> load()}
  end

  def handle_info({:new_dish, dish, {:error, _changeset}}, socket) do
    {:noreply,
     socket
     |> assign(:adding, nil)
     |> put_flash(
       :error,
       "#{dish.name} is saved in your dishes but can't be added as it is: check its details"
     )
     |> load()}
  end

  # A typed weight: "5.2", "5,2" or "5". Anything else, or out of range, is an error.
  defp parse_size(text) when is_binary(text) do
    case text |> String.trim() |> String.replace(",", ".") |> Float.parse() do
      {size, ""} when size > 0 and size < 100 -> {:ok, size}
      _ -> :error
    end
  end

  defp parse_size(_), do: :error

  # Library dishes matching the picker's search box.
  defp matching_saved(saved, ""), do: saved

  defp matching_saved(saved, q) do
    q = String.downcase(String.trim(q))
    Enum.filter(saved, &String.contains?(String.downcase(&1.name), q))
  end

  defp form_id(%MealDish{id: id}), do: "dish-#{id}"

  defp card_form(%MealDish{} = d, invalid) do
    Map.get(invalid, d.id) || to_form(Meals.change_meal_dish(d), id: form_id(d))
  end

  defp oven_options(kitchen),
    do: [{"Choose for me", ""} | for(o <- kitchen, o.kind == :oven, do: {o.name, o.id})]

  # The usual courses, plus the dish's own value if it's something else.
  defp serve_options(current) do
    presets = MealDish.serve_offset_options()

    if current in [nil | Enum.map(presets, &elem(&1, 1))],
      do: presets,
      else: presets ++ [{"Custom · #{offset_label(current)}", current}]
  end

  defp offset_label(m) when m < 0, do: "#{Duration.format(-m)} before"
  defp offset_label(m), do: "#{Duration.format(m)} after"

  defp temp_text({t, :gas_mark}),
    do: "gas #{CookingScheduler.Kitchen.Appliance.fmt_temp(t, :gas_mark)}"

  defp temp_text({t, unit}),
    do:
      "#{CookingScheduler.Kitchen.Appliance.fmt_temp(t, unit)} #{CookingScheduler.Kitchen.Appliance.temp_unit_label(unit)}"

  defp appliance_options(kitchen),
    do: [{"Choose…", ""} | for(a <- kitchen, a.kind == :other, do: {a.name, a.id})]

  defp method_icon(:oven), do: "hero-fire"
  defp method_icon(:ring), do: "hero-stop-circle"
  defp method_icon(:appliance), do: "hero-bolt"

  defp method_label(:oven), do: "Oven"
  defp method_label(:ring), do: "Hob"
  defp method_label(:appliance), do: "Appliance"

  # ---- kitchen load ---------------------------------------------------------

  attr :load, :list, required: true
  attr :serve, :integer, required: true
  attr :events, :list, default: []

  # One block per appliance, split into slots: each dish gets its own bar across its time on the heat.
  defp kitchen_load(assigns) do
    start =
      assigns.load
      |> Enum.flat_map(& &1.segments)
      |> Enum.map(& &1.from)
      |> Enum.min()
      |> div(60)
      |> Kernel.*(60)

    span = max(assigns.serve - start, 1)
    hours = for t <- Range.new(div(start, 60) * 60 + 60, assigns.serve, 60), do: t

    assigns = assign(assigns, start: start, span: span, hours: hours)

    ~H"""
    <section
      id="kitchen-load"
      class="pop-in mt-5 rounded-2xl border border-base-300 bg-base-100/90 p-4 shadow-sm backdrop-blur"
    >
      <div class="mb-2 flex flex-wrap items-baseline justify-between gap-x-4">
        <h2 class="text-sm font-semibold">Kitchen load</h2>
        <p class="text-xs text-base-content/60">
          Each dish has its own bar for its time on the heat. Dashed boxes are free oven space; a longer rest frees the oven sooner.
        </p>
      </div>

      <div class="grid grid-cols-[minmax(6rem,9rem)_1fr] items-center gap-x-3 gap-y-2">
        <div></div>
        <div class="relative h-4 text-[10px] tabular-nums text-base-content/50">
          <span
            :for={t <- @hours}
            class="absolute -translate-x-1/2"
            style={"left: #{pct(t - @start, @span)}%"}
          >
            {Duration.clock(Integer.mod(t, 1440))}
          </span>
        </div>

        <%= for row <- @load do %>
          <div class="min-w-0">
            <div class={[
              "truncate text-sm font-medium",
              row.slots == [] && "text-base-content/50"
            ]}>
              {row.name}
            </div>
            <div class={["text-xs", load_text(row)]}>{load_summary(row)}</div>
          </div>
          <div
            id={"load-#{row.id}"}
            class="relative rounded-lg bg-base-200 p-1"
          >
            <span
              :for={t <- @hours}
              class="pointer-events-none absolute inset-y-0 w-px bg-base-300"
              style={"left: #{pct(t - @start, @span)}%"}
            ></span>
            <div
              id={"load-#{row.id}-slots"}
              class="relative"
              style={"height: #{slot_height(row)}rem"}
            >
              <div
                :if={slot_top(row) > row.capacity}
                class="pointer-events-none absolute inset-x-0 z-10 border-t border-dashed border-error/70"
                style={"bottom: #{pct(row.capacity, slot_top(row))}%"}
                title="Oven full"
              >
              </div>
              <div
                :for={
                  {box, i} <-
                    if(row.kind != :other or row.slots == [],
                      do: Enum.with_index(Planner.free_space(row, @start, @serve)),
                      else: []
                    )
                }
                id={"load-free-#{row.id}-#{i}"}
                class="pointer-events-none absolute p-px"
                style={"left: #{pct(box.from - @start, @span)}%; width: #{pct(box.to - box.from, @span)}%; bottom: #{pct(box.offset, slot_top(row))}%; height: #{pct(box.units, slot_top(row))}%"}
              >
                <div class="flex h-full items-center justify-center overflow-hidden rounded-md border border-dashed border-success/50 bg-success/5 px-1 text-[10px] font-medium text-success/80">
                  <span :if={box.units >= 2 or row.kind == :rings} class="truncate">
                    {free_label(row, box.units)}
                  </span>
                </div>
              </div>
              <a
                :for={bar <- row.slots}
                id={"load-bar-#{bar.entry.dish.id}"}
                href={"#dish-card-#{bar.entry.dish.id}"}
                phx-click={
                  JS.push("show_dish", value: %{id: bar.entry.dish.id})
                  |> JS.transition({"ring-2 ring-primary/50", "", ""},
                    to: "#dish-card-#{bar.entry.dish.id}",
                    time: 1200
                  )
                }
                aria-label={"Go to #{bar.entry.dish.name}"}
                class="group absolute cursor-pointer p-px outline-none hover:z-20 focus:z-20"
                style={"left: #{pct(bar.entry.cook_at - @start, @span)}%; width: #{pct(bar.entry.out_at - bar.entry.cook_at, @span)}%; bottom: #{pct(bar.offset, slot_top(row))}%; height: #{pct(bar.units, slot_top(row))}%"}
              >
                <div class={[
                  "flex h-full items-center gap-1 overflow-hidden rounded-md border px-1.5 text-xs font-medium shadow-sm transition duration-150 group-hover:-translate-y-px group-hover:shadow-md group-focus:ring-2 group-focus:ring-primary/40",
                  bar_color(row, bar)
                ]}>
                  <.icon
                    :if={bar.over?}
                    name="hero-exclamation-triangle-micro"
                    class="size-3.5 shrink-0"
                  />
                  <span class="truncate">{bar.entry.dish.name}</span>
                  <span
                    :if={row.kind == :oven}
                    class="ml-auto shrink-0 pl-1 text-[10px] font-normal opacity-60"
                  >
                    {share_label(bar.entry.dish.oven_share)}
                  </span>
                </div>
                <div
                  role="tooltip"
                  class={[
                    "pointer-events-none invisible absolute bottom-full z-30 mb-2 w-max max-w-64 translate-y-1 rounded-xl border border-base-300 bg-base-100 p-3 text-left opacity-0 shadow-xl shadow-base-content/10 transition duration-150 group-hover:visible group-hover:translate-y-0 group-hover:opacity-100 group-focus:visible group-focus:translate-y-0 group-focus:opacity-100",
                    tip_align(bar.entry.cook_at, bar.entry.out_at, @start, @span)
                  ]}
                >
                  <div class="text-sm font-semibold">{bar.entry.dish.name}</div>
                  <div class="mt-0.5 text-xs tabular-nums text-base-content/60">
                    {Duration.clock(Integer.mod(bar.entry.cook_at, 1440))} – {Duration.clock(
                      Integer.mod(bar.entry.out_at, 1440)
                    )}
                    <span :if={row.kind == :oven}>
                      · {share_label(bar.entry.dish.oven_share)} of the oven
                    </span>
                    <span :if={row.kind == :rings and row.capacity > 1}>
                      · on {bar.entry.resource.name}
                    </span>
                  </div>
                  <div :if={bar.over?} class="mt-1.5 text-xs font-semibold text-error">
                    {if row.kind == :oven,
                      do: "Oven over capacity while this is in",
                      else: "More dishes than rings while this is on"}
                  </div>
                </div>
              </a>
            </div>
          </div>
        <% end %>
      </div>

      <div
        :if={@events != []}
        id="oven-events"
        class="mt-3 flex flex-wrap gap-1.5 border-t border-base-300 pt-3"
      >
        <span
          :for={ev <- @events}
          id={"oven-event-#{String.replace(ev.id, ":", "-")}"}
          class="inline-flex items-center gap-1.5 rounded-full bg-base-200 px-2.5 py-1 text-xs"
        >
          <.icon
            name={
              if ev.kind == :preheat, do: "hero-power-micro", else: "hero-adjustments-vertical-micro"
            }
            class="size-3.5 text-primary"
          />
          <span class="font-semibold tabular-nums">{Duration.clock(ev.at)}</span>
          <span>
            {if ev.kind == :preheat,
              do: "Switch on #{ev.appliance.name}",
              else: "#{ev.appliance.name} to"}
            <b>{temp_text(ev.temp)}</b>
            <span class="opacity-60">for {ev.dish.name}</span>
          </span>
        </span>
      </div>
    </section>
    """
  end

  defp pct(minutes, span), do: Float.round(minutes / span * 100, 2)

  # Full height in units: the appliance's capacity, or higher if it is overfilled.
  defp slot_top(row),
    do: Enum.reduce(row.slots, row.capacity, &max(&1.offset + &1.units, &2))

  # A whole oven is 6rem tall (half a rem per twelfth); one-at-a-time appliances get 2rem.
  # Idle appliances get a short row so the busy ones stand out.
  # Idle rows stay short, but an idle ring row keeps a lane per ring so 2 rings look like 2.
  defp slot_height(%{slots: [], kind: :rings, capacity: n}), do: max(n, 2) * 1.25
  defp slot_height(%{slots: []}), do: 2
  defp slot_height(%{kind: :oven} = row), do: slot_top(row) * 0.5
  defp slot_height(row), do: slot_top(row) * 2

  defp free_label(%{slots: []}, _units), do: "Free"
  defp free_label(%{capacity: units}, units), do: "Free"
  defp free_label(%{kind: :rings}, _units), do: "Ring free"

  defp free_label(_row, units) do
    g = Integer.gcd(units, 12)
    "#{div(units, g)}/#{div(12, g)} free"
  end

  defp bar_color(_row, %{over?: true}), do: "border-error/60 bg-error/15 text-error"

  defp bar_color(%{kind: kind}, _bar) when kind != :oven,
    do: "border-info/40 bg-info/15 text-base-content group-hover:bg-info/25"

  defp bar_color(_row, _bar),
    do: "border-primary/40 bg-primary/15 text-base-content group-hover:bg-primary/25"

  defp load_summary(%{slots: []}), do: "Not used"

  defp load_summary(%{kind: :rings, capacity: n} = row) when n > 1 do
    cond do
      row.peak > n -> "Over capacity"
      row.peak == n -> "All #{n} on at peak"
      true -> "Up to #{row.peak} of #{n} on"
    end
  end

  defp load_summary(%{kind: kind} = row) when kind != :oven do
    "#{length(row.segments)} #{if length(row.segments) == 1, do: "stretch", else: "stretches"} in use"
  end

  defp load_summary(row) do
    cond do
      row.peak > row.capacity -> "Over capacity"
      row.peak == row.capacity -> "Full at peak"
      true -> "Peak #{round(row.peak / row.capacity * 100)}% full"
    end
  end

  defp load_text(%{kind: kind} = row) when kind != :oven,
    do: if(row.peak > row.capacity, do: "font-semibold text-error", else: "text-base-content/60")

  defp load_text(row) do
    cond do
      row.peak > row.capacity -> "font-semibold text-error"
      row.peak == row.capacity -> "font-semibold text-warning"
      row.peak * 4 >= row.capacity * 3 -> "text-warning"
      true -> "text-base-content/60"
    end
  end

  defp share_label(share) do
    Enum.find_value(MealDish.oven_share_options(), "", fn {l, v} ->
      v == (share || :third) && l
    end)
  end

  # Keep tooltips on screen: anchor to the left/right edge near the ends of the strip.
  defp tip_align(from, to, start, span) do
    mid = (from + to) / 2 - start

    cond do
      mid / span < 0.25 -> "left-0"
      mid / span > 0.75 -> "right-0"
      true -> "left-1/2 -translate-x-1/2"
    end
  end

  # ---- components -----------------------------------------------------------

  attr :f, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :options, :list, default: []
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(placeholder step min)

  # A compact field with a small label above the box.
  defp mini(%{type: "select"} = assigns) do
    ~H"""
    <div class={["grid min-w-0 gap-1", @class]}>
      <.mini_label label={@label} for={@f.id} />
      <select
        id={@f.id}
        name={@f.name}
        class={["select select-sm w-full", @f.errors != [] && "select-error"]}
        {@rest}
      >
        {Phoenix.HTML.Form.options_for_select(@options, @f.value)}
      </select>
    </div>
    """
  end

  defp mini(assigns) do
    ~H"""
    <div class={["grid min-w-0 gap-1", @class]}>
      <.mini_label label={@label} for={@f.id} />
      <input
        type={@type}
        id={@f.id}
        name={@f.name}
        value={mini_value(@f.value)}
        autocomplete="off"
        class={["input input-sm w-full tabular-nums", @f.errors != [] && "input-error"]}
        {@rest}
      />
      <.mini_errors f={@f} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :for, :string, required: true

  defp mini_label(assigns) do
    ~H"""
    <label for={@for} class="ps-1 text-xs font-medium text-base-content/60">{@label}</label>
    """
  end

  attr :f, Phoenix.HTML.FormField, required: true

  defp mini_errors(assigns) do
    ~H"""
    <span :for={{msg, opts} <- @f.errors} class="mt-0.5 block text-xs leading-tight text-error">
      {translate_error({msg, opts})}
    </span>
    """
  end

  defp mini_value(v) when is_integer(v), do: Duration.format(v)

  defp mini_value(v) when is_atom(v) and not is_nil(v) and not is_boolean(v),
    do: Atom.to_string(v)

  defp mini_value(v), do: v

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  defp duration_input(assigns) do
    ~H"""
    <.mini f={@form[@field]} label={@label} placeholder="1:30" class="w-24" phx-debounce="500" />
    """
  end

  attr :label, :string, required: true
  attr :time, :integer, required: true
  attr :strong, :boolean, default: false

  defp step(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-baseline gap-1 rounded-full px-2 py-0.5 text-xs",
      @strong && "bg-primary/10 text-primary",
      !@strong && "bg-base-200"
    ]}>
      <span class="uppercase tracking-wide opacity-60">{@label}</span>
      <span class="font-semibold tabular-nums">{Duration.clock(@time)}</span>
    </span>
    """
  end

  attr :entry, :any, required: true

  defp timeline(assigns) do
    ~H"""
    <div
      :if={@entry.dish.cook_minutes > 0}
      class="flex flex-wrap items-center gap-1"
    >
      <.step :if={@entry.dish.prep_minutes > 0} label="Prep" time={@entry.prep_at} />
      <.step label={start_label(@entry.dish.method)} time={@entry.cook_at} strong />
      <.step
        label={
          if @entry.dish.rest_minutes > 0, do: out_label(@entry.dish.method), else: "Out & serve"
        }
        time={@entry.out_at}
      />
      <.step :if={@entry.dish.rest_minutes > 0} label="Serve" time={@entry.serve_at} />
      <span
        :if={@entry.dish.serve_offset_minutes != 0}
        class="badge badge-accent badge-soft badge-sm"
        title="Served at a different time from the main"
      >
        {MealDish.course(@entry.dish.serve_offset_minutes)}
      </span>
    </div>
    """
  end

  defp start_label(:oven), do: "In"
  defp start_label(:ring), do: "On"
  defp start_label(:appliance), do: "Start"

  defp out_label(:oven), do: "Out"
  defp out_label(:ring), do: "Off"
  defp out_label(:appliance), do: "Done"

  # What a closed row says about the dish's settings, so it doesn't need its inputs on show.
  defp summary(d) do
    [
      MealDish.sized?(d) && MealDish.size_text(d.size, d.size_unit),
      d.prep_minutes > 0 && "#{Duration.format(d.prep_minutes)} prep#{prep_when(d.prep_day)}",
      if(d.cook_minutes > 0,
        do: "#{Duration.format(d.cook_minutes)} cook",
        else: "No cooking time"
      ),
      d.rest_minutes > 0 && "#{Duration.format(d.rest_minutes)} rest",
      MealDish.done_temp_text(d),
      d.method == :oven && d.temp && temp_text({d.temp, d.temp_unit}),
      d.method == :oven && share_text(d.oven_share),
      d.method == :ring && d.ring_size &&
        "#{d.ring_size |> Atom.to_string() |> String.capitalize()} ring"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp prep_when(:day_before), do: " the day before"
  defp prep_when(:morning_of), do: " in the morning"
  defp prep_when(_), do: ""

  defp share_text(share) do
    case List.keyfind(MealDish.oven_share_options(), share, 1) do
      {"Whole oven", _} -> "whole oven"
      {label, _} -> "#{String.downcase(label)} oven"
      nil -> nil
    end
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp field_group(assigns) do
    ~H"""
    <div class="grid items-start gap-1.5 sm:grid-cols-[5.5rem_1fr]">
      <span class="pt-0.5 text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
        {@label}
      </span>
      <div class="flex flex-wrap items-start gap-x-2 gap-y-2">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :entry, :any, required: true
  attr :form, :any, required: true
  attr :kitchen, :list, required: true
  attr :fixes, :list, default: []
  attr :open, :boolean, default: false

  # One line per dish: name, what it's set to, and when it happens. Tapping it opens the
  # settings underneath (ADR 0026).
  defp dish_card(assigns) do
    assigns = assign(assigns, :dish, assigns.entry.dish)

    ~H"""
    <li
      id={"dish-card-#{@dish.id}"}
      class={[
        "pop-in scroll-mt-28 rounded-xl border bg-base-100/90 shadow-sm backdrop-blur transition",
        @open && "border-primary/30 shadow-md",
        !@open && "border-base-300 hover:border-base-content/20 hover:shadow-md"
      ]}
    >
      <.form for={@form} id={@form.id <> "-form"} phx-change="update">
        <input type="hidden" name="meal_dish_id" value={@dish.id} />

        <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5 px-3 py-2">
          <button
            type="button"
            id={"toggle-dish-#{@dish.id}"}
            phx-click="toggle_dish"
            phx-value-id={@dish.id}
            aria-expanded={to_string(@open)}
            aria-controls={"settings-#{@dish.id}"}
            class="group flex min-w-0 flex-1 basis-60 cursor-pointer items-center gap-2.5 rounded-lg text-left"
          >
            <span
              class="grid size-8 shrink-0 place-items-center rounded-lg bg-base-200 text-base-content/70 transition group-hover:bg-primary/10 group-hover:text-primary"
              title={method_label(@dish.method)}
            >
              <.icon name={method_icon(@dish.method)} class="size-4" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="block truncate font-semibold leading-tight">{@dish.name}</span>
              <span class="block truncate text-xs text-base-content/55">{summary(@dish)}</span>
            </span>
          </button>

          <.timeline entry={@entry} />

          <span :if={@entry.resource} class="badge badge-secondary badge-soft badge-sm gap-1">
            {@entry.resource.name}
            <span :if={@entry.source == :suggested} class="opacity-60">· auto</span>
          </span>

          <div class="ml-auto flex items-center">
            <button
              type="button"
              phx-click="toggle_dish"
              phx-value-id={@dish.id}
              class={["btn btn-xs btn-circle btn-ghost", @open && "text-primary"]}
              aria-label={if(@open, do: "Close #{@dish.name}", else: "Edit #{@dish.name}")}
              title={if(@open, do: "Done", else: "Edit")}
            >
              <.icon
                name="hero-chevron-down"
                class={["size-4 transition-transform duration-200", @open && "rotate-180"]}
              />
            </button>
            <.link
              id={"view-dish-#{@dish.id}"}
              navigate={~p"/meals/#{@dish.meal_id}/dishes/#{@dish.id}"}
              class="btn btn-xs btn-circle btn-ghost"
              aria-label={"Details and ingredients for #{@dish.name}"}
              title="Details & ingredients"
            >
              <.icon name="hero-eye" class="size-4" />
            </.link>
            <.confirm_button
              id={"delete-dish-#{@dish.id}"}
              title={"Remove #{@dish.name} from this meal?"}
              message="Its saved version stays in your dishes."
              confirm_label="Remove"
              tone={:danger}
              on_confirm={JS.push("delete", value: %{id: @dish.id})}
              class="btn btn-xs btn-circle btn-ghost hover:text-error"
              aria-label={"Remove #{@dish.name}"}
            >
              <.icon name="hero-trash" class="size-4" />
            </.confirm_button>
          </div>
        </div>

        <div :if={@entry.issues != []} class="flex flex-wrap items-center gap-1.5 px-3 pb-2">
          <span
            :for={issue <- @entry.issues}
            class="badge badge-warning badge-soft h-auto gap-1 whitespace-normal py-0.5 text-left"
          >
            <.icon name="hero-exclamation-triangle-micro" class="size-3.5 shrink-0" /> {issue}
          </span>
          <span :if={@fixes != []} class="ml-1 text-xs text-base-content/60">Try:</span>
          <button
            :for={{fix, i} <- Enum.with_index(@fixes)}
            type="button"
            id={"fix-#{@dish.id}-#{i}"}
            class="btn btn-xs btn-primary btn-soft rounded-full"
            phx-click="apply_fix"
            phx-value-dish={@dish.id}
            phx-value-index={i}
          >
            <.icon name="hero-sparkles-micro" class="size-3" /> {fix.label}
          </button>
        </div>

        <%!-- settings: always in the form so autosave sees every field, shown when open --%>
        <div
          id={"settings-#{@dish.id}"}
          class={[
            "grid gap-2.5 border-t border-base-300 px-3 pb-3 pt-3",
            !@open && "hidden"
          ]}
        >
          <.field_group label="Dish">
            <.mini f={@form[:name]} label="Name" class="w-full max-w-md" phx-debounce="400" />
          </.field_group>

          <.field_group label="Done when">
            <.mini
              f={@form[:done_temp]}
              label="Inside temp"
              type="number"
              step="any"
              placeholder="74"
              class="w-28"
              phx-debounce="500"
            />
            <.mini
              f={@form[:done_temp_unit]}
              label="Scale"
              type="select"
              class="w-24"
              options={MealDish.done_temp_unit_options()}
            />
          </.field_group>

          <.field_group label="Timing">
            <.duration_input form={@form} field={:prep_minutes} label="Prep" />
            <.mini
              :if={MealDish.sized?(@dish)}
              f={@form[:size]}
              label={"Weight (#{@dish.size_unit || :kg})"}
              inputmode="decimal"
              class="w-24"
              phx-debounce="500"
              title={"Sets the cook time: #{MealDish.rule_text(@dish)}"}
            />
            <.duration_input form={@form} field={:cook_minutes} label="Cook" />
            <.duration_input form={@form} field={:rest_minutes} label="Rest" />
            <.mini
              :if={@dish.prep_minutes > 0}
              f={@form[:prep_day]}
              label="Prep when"
              type="select"
              class="w-52"
              options={MealDish.prep_day_options()}
            />
            <.mini
              f={@form[:serve_offset_minutes]}
              label="Serve with"
              type="select"
              class="w-52"
              options={serve_options(@dish.serve_offset_minutes)}
            />
          </.field_group>

          <.field_group label={
            if(@dish.method == :oven, do: "Oven", else: method_label(@dish.method))
          }>
            <%= if @dish.method == :oven do %>
              <.mini
                f={@form[:temp]}
                label="Temp"
                type="number"
                step="any"
                class="w-28"
                phx-debounce="500"
              />
              <.mini
                f={@form[:temp_unit]}
                label="Scale"
                type="select"
                class="w-36"
                options={[{"Gas mark", :gas_mark}, {"°C", :celsius}, {"°F", :fahrenheit}]}
              />
              <.mini
                f={@form[:oven_share]}
                label="Space"
                type="select"
                class="w-44"
                options={MealDish.oven_share_options()}
              />
              <.mini
                f={@form[:appliance_id]}
                label="Oven"
                type="select"
                class="w-48"
                options={oven_options(@kitchen)}
              />
            <% end %>
            <.mini
              :if={@dish.method == :ring}
              f={@form[:ring_size]}
              label="Ring"
              type="select"
              class="w-36"
              options={[{"Small", :small}, {"Medium", :medium}, {"Large", :large}]}
            />
            <.mini
              :if={@dish.method == :appliance}
              f={@form[:appliance_id]}
              label="Use"
              type="select"
              class="w-48"
              options={appliance_options(@kitchen)}
            />
          </.field_group>

          <.field_group label="Notes">
            <div class="grid w-full gap-x-4 sm:grid-cols-2">
              <.input
                field={@form[:notes]}
                type="textarea"
                rows="2"
                placeholder="Notes"
                phx-debounce="400"
              />
              <div>
                <.input
                  field={@form[:link]}
                  type="text"
                  placeholder="Recipe link: https://…"
                  phx-debounce="400"
                />
                <div class="flex flex-wrap items-center gap-x-6">
                  <.input field={@form[:ingredients_in]} type="checkbox" label="All ingredients in" />
                  <.input field={@form[:prepped]} type="checkbox" label="Prepped" />
                  <a
                    :if={@dish.link not in [nil, ""]}
                    href={@dish.link}
                    target="_blank"
                    rel="noopener"
                    class="link link-hover mb-2 inline-flex items-center gap-1 text-sm text-primary"
                  >
                    <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" /> Open recipe
                  </a>
                </div>
              </div>
            </div>
          </.field_group>
        </div>
      </.form>
    </li>
    """
  end

  attr :sizing, :map, required: true

  # A sized dish's weight step (ADR 0029): the weight (last time's to start with), the cook
  # time it gives, and which version to start from: the saved recipe or a past one.
  defp sizing_panel(assigns) do
    %{dish: dish, weight: weight} = assigns.sizing

    cook =
      case parse_size(weight) do
        {:ok, size} -> MealDish.cook_for_size(dish, size)
        :error -> nil
      end

    assigns = assign(assigns, dish: dish, cook: cook, invalid: weight != "" and is_nil(cook))

    ~H"""
    <div id="sizing-panel" class="pop-in">
      <button
        type="button"
        id="sizing-back"
        phx-click="unsize"
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> Your dishes
      </button>

      <.form
        for={%{}}
        as={:sizing}
        id="sizing-form"
        phx-change="size_change"
        phx-submit="add_sized"
      >
        <div class="flex items-center gap-3">
          <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
            <.icon name="hero-scale" class="size-5" />
          </span>
          <div class="min-w-0">
            <h3 class="truncate text-base font-bold">{@dish.name}</h3>
            <p class="text-xs text-base-content/60">{MealDish.rule_text(@dish)}</p>
          </div>
        </div>

        <div class="mt-4 flex flex-wrap items-end gap-3">
          <label class="grid gap-1">
            <span class="ps-1 text-xs font-medium text-base-content/60">How heavy is it?</span>
            <span class={["input w-40", @invalid && "input-error"]}>
              <input
                type="text"
                inputmode="decimal"
                id="sizing-weight"
                name="sizing[weight]"
                value={@sizing.weight}
                placeholder="5.2"
                autocomplete="off"
                phx-debounce="200"
                phx-mounted={JS.focus()}
                class="w-full text-lg font-bold tabular-nums"
              />
              <span class="text-sm text-base-content/50">{@dish.size_unit || :kg}</span>
            </span>
          </label>
          <div
            id="sizing-cook"
            class={[
              "rounded-xl px-3 py-2 text-sm transition",
              @cook && "bg-primary/10 text-primary",
              !@cook && "bg-base-200 text-base-content/50"
            ]}
          >
            <%= cond do %>
              <% @cook -> %>
                <span class="font-bold tabular-nums">{Duration.format(@cook)}</span> cook
              <% @invalid -> %>
                Type a weight, like 5.2
              <% true -> %>
                Cook time follows the weight
            <% end %>
          </div>
        </div>

        <fieldset :if={@sizing.history != []} class="mt-5">
          <legend class="mb-2 text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
            Start from
          </legend>
          <div id="sizing-versions" class="grid gap-1.5">
            <.version_option
              id="version-saved"
              value=""
              checked={@sizing.from == ""}
              title="Your saved recipe"
              detail="Its notes, temperature and ingredients as they are now"
            />
            <.version_option
              :for={h <- @sizing.history}
              id={"version-#{h.meal_dish.id}"}
              value={to_string(h.meal_dish.id)}
              checked={@sizing.from == to_string(h.meal_dish.id)}
              title={h.meal.name}
              detail={version_detail(h)}
              note={h.meal_dish.next_time}
              late={h.lateness}
            />
          </div>
        </fieldset>

        <div class="mt-5 flex justify-end">
          <button
            id="add-sized"
            type="submit"
            disabled={is_nil(@cook)}
            class="btn btn-primary rounded-full"
          >
            <.icon name="hero-plus-micro" class="size-4" /> Add to meal
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, required: true
  attr :title, :string, required: true
  attr :detail, :string, required: true
  attr :note, :string, default: nil
  attr :late, :integer, default: nil

  defp version_option(assigns) do
    ~H"""
    <label
      id={@id}
      class={[
        "flex cursor-pointer items-start gap-3 rounded-xl border px-3 py-2 transition",
        @checked && "border-primary/50 bg-primary/5 shadow-sm",
        !@checked && "border-base-300 bg-base-100/70 hover:border-base-content/20"
      ]}
    >
      <input
        type="radio"
        name="sizing[from]"
        value={@value}
        checked={@checked}
        class="radio radio-primary radio-sm mt-0.5"
      />
      <span class="min-w-0 flex-1">
        <span class="flex flex-wrap items-baseline gap-x-2">
          <span class="font-semibold">{@title}</span>
          <span
            :if={@late}
            class={[
              "text-xs",
              @late > 0 && "font-semibold text-warning",
              @late <= 0 && "text-success"
            ]}
          >
            {lateness_text(@late)}
          </span>
        </span>
        <span class="block text-xs text-base-content/60">{@detail}</span>
        <span
          :if={@note not in [nil, ""]}
          class="mt-1 block whitespace-pre-line rounded-lg bg-accent/15 px-2 py-1 text-xs"
        >
          {@note}
        </span>
      </span>
    </label>
    """
  end

  defp version_detail(%{meal: m, meal_dish: d}) do
    [
      Calendar.strftime(m.date, "%d %b %Y"),
      MealDish.size_text(d.size, d.size_unit),
      "planned #{Duration.format(d.cook_minutes)}, took #{Duration.format(Meals.actual_cook(d))}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp lateness_text(0), do: "on time"
  defp lateness_text(m) when m > 0, do: "#{Duration.format(m)} late"
  defp lateness_text(m), do: "#{Duration.format(-m)} early"

  # " · cooked 3 times, last 5.2 kg" for the picker row.
  defp versions_text([]), do: ""

  defp versions_text([%{meal_dish: last} | _] = history) do
    times = if length(history) == 1, do: "once", else: "#{length(history)} times"
    last = MealDish.size_text(last.size, last.size_unit)
    " · cooked #{times}" <> if(last, do: ", last #{last}", else: "")
  end

  attr :tab, :atom, required: true
  attr :meal, Meal, required: true
  attr :saved, :list, required: true
  attr :query, :string, required: true
  attr :socket, Phoenix.LiveView.Socket, required: true
  attr :other_meals, :list, required: true
  attr :from_meal, :any, default: nil
  attr :entries, :list, required: true
  attr :sizing, :any, default: nil
  attr :histories, :map, default: %{}

  # "Add a dish": pick one from the library, or create a new one with the New dish form
  # rendered inside the modal (see ADR 0017).
  defp add_dish_modal(assigns) do
    assigns = assign(assigns, :matching, matching_saved(assigns.saved, assigns.query))

    ~H"""
    <div
      id="add-dish-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-dish-title"
      class="fixed inset-0 z-[100] flex items-end justify-center p-0 sm:items-center sm:p-4"
      phx-window-keydown="close_add"
      phx-key="escape"
    >
      <div class="absolute inset-0 bg-base-content/30 backdrop-blur-sm" phx-click="close_add"></div>
      <div
        id="add-dish-panel"
        class="glass pop-in relative flex max-h-[92vh] w-full max-w-2xl flex-col rounded-t-[1.75rem] shadow-2xl sm:max-h-[85vh] sm:rounded-[1.75rem]"
      >
        <div class="flex items-center justify-between gap-3 px-6 pt-5">
          <h2 id="add-dish-title" class="text-lg font-bold tracking-tight">Add a dish</h2>
          <button
            type="button"
            class="btn btn-xs btn-circle btn-ghost"
            phx-click="close_add"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div role="tablist" class="mx-6 mt-3 flex gap-1 rounded-full bg-base-200/70 p-1">
          <button
            :for={
              {tab, id, label} <- [
                {:pick, "add-tab-pick", "Your dishes (#{length(@saved)})"},
                {:meal, "add-tab-meal", "From a meal"},
                {:new, "add-tab-new", "New dish"}
              ]
            }
            id={id}
            type="button"
            role="tab"
            aria-selected={to_string(@tab == tab)}
            phx-click="add_tab"
            phx-value-tab={tab}
            class={[
              "flex-1 rounded-full px-3 py-1.5 text-sm font-medium transition",
              @tab == tab && "bg-base-100 shadow-sm",
              @tab != tab && "text-base-content/60 hover:text-base-content"
            ]}
          >
            {label}
          </button>
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto px-6 pb-6 pt-4">
          <%= if @tab == :meal do %>
            <form id="from-meal-form" phx-change="pick_from_meal" class="mb-3">
              <select name="meal" class="select select-sm w-full" aria-label="Meal to copy from">
                <option value="">Choose a meal…</option>
                <option
                  :for={m <- @other_meals}
                  value={m.id}
                  selected={@from_meal && @from_meal.meal.id == m.id}
                >
                  {m.name} · {Calendar.strftime(m.date, "%d %b %Y")}
                </option>
              </select>
            </form>
            <p :if={@other_meals == []} class="text-sm text-base-content/60">No other meals yet.</p>
            <ul :if={@from_meal} id="from-meal-dishes" class="grid gap-1.5">
              <li :for={d <- @from_meal.dishes}>
                <div class="flex w-full items-center gap-3 rounded-xl border border-base-300 bg-base-100/70 px-3 py-2">
                  <span
                    class="grid size-8 shrink-0 place-items-center rounded-lg bg-base-200 text-base-content/70"
                    title={method_label(d.method)}
                  >
                    <.icon name={method_icon(d.method)} class="size-4" />
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block truncate font-semibold">{d.name}</span>
                    <span class="block truncate text-xs text-base-content/60">
                      {Duration.format(d.cook_minutes)} cook<span :if={d.cook_done_at}>
                        · cooked last time
                      </span>
                    </span>
                  </span>
                  <span
                    :if={
                      Enum.any?(@entries, &(String.downcase(&1.dish.name) == String.downcase(d.name)))
                    }
                    class="text-xs text-base-content/50"
                  >
                    Already in
                  </span>
                  <button
                    :if={
                      not Enum.any?(
                        @entries,
                        &(String.downcase(&1.dish.name) == String.downcase(d.name))
                      )
                    }
                    type="button"
                    id={"add-from-meal-#{d.id}"}
                    phx-click="add_from_meal"
                    phx-value-id={d.id}
                    class="btn btn-xs btn-primary btn-soft rounded-full"
                  >
                    <.icon name="hero-plus-micro" class="size-3.5" /> Add
                  </button>
                </div>
              </li>
            </ul>
          <% end %>
          <%= if @tab == :pick and @sizing do %>
            <.sizing_panel sizing={@sizing} />
          <% end %>
          <%= if @tab == :pick and is_nil(@sizing) do %>
            <form id="saved-filter" phx-change="filter_saved" phx-submit="filter_saved" class="mb-3">
              <label class="input input-sm w-full">
                <.icon name="hero-magnifying-glass-micro" class="size-4 opacity-50" />
                <input
                  type="search"
                  name="q"
                  value={@query}
                  placeholder="Search your dishes…"
                  autocomplete="off"
                  phx-debounce="150"
                  phx-mounted={JS.focus()}
                />
              </label>
            </form>

            <ul :if={@matching != []} id="saved-picker" class="grid gap-1.5">
              <li :for={s <- @matching}>
                <button
                  type="button"
                  id={"saved-#{s.id}"}
                  phx-click={if MealDish.sized?(s), do: "size_saved", else: "add_saved"}
                  phx-value-id={s.id}
                  class="group flex w-full items-center gap-3 rounded-xl border border-base-300 bg-base-100/70 px-3 py-2 text-left transition hover:border-primary/40 hover:bg-base-100"
                >
                  <span
                    class="grid size-8 shrink-0 place-items-center rounded-lg bg-base-200 text-base-content/70"
                    title={method_label(s.method)}
                  >
                    <.icon name={method_icon(s.method)} class="size-4" />
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block truncate font-semibold">{s.name}</span>
                    <span class="block truncate text-xs text-base-content/60">
                      <%= if MealDish.sized?(s) do %>
                        <.icon name="hero-scale-micro" class="size-3 -mt-0.5 inline" />
                        {MealDish.rule_text(s)}{versions_text(Map.get(@histories, s.id, []))}
                      <% else %>
                        {Duration.format(s.cook_minutes)} cook
                      <% end %>
                      <span :if={s.tags != []}>· {Enum.join(s.tags, ", ")}</span>
                    </span>
                  </span>
                  <span class="btn btn-xs btn-primary btn-soft rounded-full opacity-70 transition group-hover:opacity-100">
                    <%= if MealDish.sized?(s) do %>
                      Weigh <.icon name="hero-chevron-right-micro" class="size-3.5" />
                    <% else %>
                      <.icon name="hero-plus-micro" class="size-3.5" /> Add
                    <% end %>
                  </span>
                </button>
              </li>
            </ul>

            <p
              :if={@matching == []}
              class="rounded-xl border border-dashed border-base-300 p-6 text-center text-sm text-base-content/60"
            >
              <%= if @saved == [] do %>
                Every dish you make is kept here for next time. Start with a new one.
              <% else %>
                Nothing matches "{@query}".
              <% end %>
              <button
                type="button"
                class="link link-hover ml-1 text-primary"
                phx-click="add_tab"
                phx-value-tab="new"
              >
                Create a new dish
              </button>
            </p>
          <% end %>
          <%= if @tab == :new do %>
            {live_render(@socket, CookingSchedulerWeb.DishFormLive,
              id: "new-dish-form",
              session: %{"meal_id" => @meal.id}
            )}
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        navigate={~p"/"}
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> All meals
      </.link>

      <.form
        for={@meal_form}
        id="meal-form"
        phx-change="update_meal"
        class="flex flex-wrap items-center justify-between gap-4"
      >
        <div class="min-w-0 flex-1 basis-80">
          <input
            type="text"
            id={@meal_form[:name].id}
            name={@meal_form[:name].name}
            value={@meal_form[:name].value}
            aria-label="Meal name"
            phx-debounce="400"
            class="input input-ghost -ml-3 h-auto w-full px-3 py-1 text-3xl font-extrabold tracking-tight sm:text-4xl"
          />
          <div class="mt-1 flex flex-wrap items-center gap-3 text-sm text-base-content/60">
            <input
              type="date"
              id={@meal_form[:date].id}
              name={@meal_form[:date].name}
              value={@meal_form[:date].value}
              aria-label="Date"
              class="input input-ghost input-sm -ml-3"
            />
            <span>Everything counts back from serving time. Changes save as you go.</span>
          </div>
        </div>

        <div class="flex items-center gap-3 rounded-2xl bg-gradient-to-br from-primary to-secondary py-2 pl-4 pr-2 text-primary-content shadow-lg shadow-primary/20">
          <.icon name="hero-bell-alert" class="size-5" />
          <span class="text-sm font-medium">Dinner at</span>
          <input
            type="time"
            id={@meal_form[:serve_at].id}
            name={@meal_form[:serve_at].name}
            value={Calendar.strftime(@meal.serve_at, "%H:%M")}
            class="input input-sm w-28 border-0 bg-white/20 text-center text-lg font-bold text-primary-content"
          />
        </div>
      </.form>

      <div class="mt-4 flex flex-wrap items-center justify-end gap-2">
        <button id="copy-meal" class="btn btn-sm btn-ghost rounded-full" phx-click="copy_meal">
          <.icon name="hero-document-duplicate" class="size-4" /> Copy as a new meal
        </button>
        <button
          :if={@meal.status in [:planning, :prepping]}
          id="prep-meal"
          class="btn btn-sm btn-secondary btn-soft rounded-full"
          phx-click="start_prepping"
        >
          <.icon name="hero-clipboard-document-check" class="size-4" />
          {if @meal.status == :planning, do: "Start prepping", else: "Open prep"}
        </button>
        <.link
          id="cook-meal"
          navigate={~p"/meals/#{@meal.id}/cook"}
          class="btn btn-sm btn-primary rounded-full"
        >
          <.icon name="hero-play" class="size-4" /> Cook this meal
        </.link>
      </div>

      <div class="mt-5 flex flex-wrap items-center gap-2">
        <button
          id="add-dish"
          class="btn btn-sm btn-primary btn-soft rounded-full"
          phx-click="open_add"
        >
          <.icon name="hero-plus" class="size-4" /> Add dish
        </button>
      </div>

      <.add_dish_modal
        :if={@adding}
        tab={@adding}
        meal={@meal}
        saved={@saved}
        query={@saved_query}
        socket={@socket}
        other_meals={@other_meals}
        from_meal={@from_meal}
        entries={@entries}
        sizing={@sizing}
        histories={@histories}
      />

      <div
        :if={@entries == []}
        class="pop-in mt-6 rounded-3xl border border-dashed border-base-300 bg-base-100/70 p-8 text-center"
      >
        <p class="text-base-content/60">No dishes in this meal yet. Add one above, or:</p>
        <div class="mt-4 flex flex-wrap items-center justify-center gap-2">
          <%!-- One picker, newest meal first, however many meals there are. --%>
          <form
            :if={@other_meals != []}
            id="copy-from-form"
            phx-submit="copy_from"
            class="flex w-full max-w-lg flex-wrap items-center justify-center gap-2"
          >
            <label class="relative min-w-0 flex-1 basis-56">
              <.icon
                name="hero-document-duplicate"
                class="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-base-content/50"
              />
              <select
                id="copy-from-meal"
                name="id"
                aria-label="Meal to copy the dishes from"
                class="select w-full rounded-full pl-10"
              >
                <option :for={m <- @other_meals} value={m.id}>
                  {m.name} · {Calendar.strftime(m.date, "%d %b %Y")}
                </option>
              </select>
            </label>
            <button id="copy-from" type="submit" class="btn btn-primary rounded-full">
              Copy its dishes
            </button>
          </form>
          <button
            :if={@other_meals == []}
            id="start-from-last-year"
            class="btn btn-primary rounded-full"
            phx-click="start_from_last_year"
          >
            <.icon name="hero-sparkles" class="size-4" /> Start from last year's menu
          </button>
        </div>
      </div>

      <.kitchen_load
        :if={Enum.any?(@load, &(&1.slots != []))}
        load={@load}
        serve={@serve}
        events={@oven_events}
      />

      <div
        :if={@problems != []}
        id="problems"
        class="pop-in mt-4 flex flex-wrap items-center gap-x-3 gap-y-1 rounded-2xl border border-warning/40 bg-warning/10 px-4 py-2.5 text-sm"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
        <span class="font-semibold">
          {length(@problems)} {if length(@problems) == 1, do: "dish needs", else: "dishes need"} a hand
        </span>
        <span class="text-base-content/70">
          {Enum.map_join(@problems, ", ", & &1.dish.name)}
        </span>
        <a href={"#dish-card-#{hd(@problems).dish.id}"} class="link link-hover ml-auto text-primary">
          Show me
        </a>
      </div>

      <div :if={@entries != []} id="dishes" class="mt-4 grid gap-2">
        <%= for section <- @sections do %>
          <h3
            id={"part-#{section.label |> String.downcase() |> String.replace(~r/[^a-z]+/, "-")}"}
            class="mt-3 flex items-center gap-3 text-xs font-semibold uppercase tracking-wider text-base-content/50 first:mt-0"
          >
            {section.label}
            <span class="h-px flex-1 bg-base-300"></span>
          </h3>
          <ul class="grid gap-2">
            <.dish_card
              :for={e <- section.entries}
              entry={e}
              form={card_form(e.dish, @invalid)}
              kitchen={@kitchen}
              fixes={Map.get(@fixes, e.dish.id, [])}
              open={
                MapSet.member?(@open, e.dish.id) or Map.has_key?(@invalid, e.dish.id) or
                  e.dish.cook_minutes == 0
              }
            />
          </ul>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
