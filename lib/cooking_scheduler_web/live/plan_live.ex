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
     |> assign(:adding, nil)
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
    {:noreply, socket |> assign(:adding, tab) |> assign(:saved_query, "")}
  end

  def handle_event("close_add", _params, socket), do: {:noreply, assign(socket, :adding, nil)}

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

  # One strip per appliance: bar height is how full it is, across the cooking window.
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
          How full each appliance is until serving. Gaps are free space; a longer rest frees the oven sooner.
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
            <div class="truncate text-sm font-medium">{row.appliance.name}</div>
            <div class={["text-xs", load_text(row)]}>{load_summary(row)}</div>
          </div>
          <div
            id={"load-#{row.appliance.id}"}
            class="relative h-10 rounded-lg bg-base-200"
          >
            <span
              :for={t <- @hours}
              class="absolute inset-y-0 w-px bg-base-300"
              style={"left: #{pct(t - @start, @span)}%"}
            ></span>
            <div
              :for={seg <- row.segments}
              tabindex="0"
              class="group absolute inset-y-0 outline-none hover:z-20 focus:z-20"
              style={"left: #{pct(seg.from - @start, @span)}%; width: #{pct(seg.to - seg.from, @span)}%"}
            >
              <div
                class={[
                  "absolute inset-x-0 bottom-0 rounded-sm transition group-hover:brightness-95 group-focus:brightness-95",
                  load_color(row, seg)
                ]}
                style={"height: #{height(seg, row)}%"}
              >
              </div>
              <div
                role="tooltip"
                class={[
                  "pointer-events-none invisible absolute bottom-full z-30 mb-2 w-max max-w-64 translate-y-1 rounded-xl border border-base-300 bg-base-100 p-3 text-left opacity-0 shadow-xl shadow-base-content/10 transition duration-150 group-hover:visible group-hover:translate-y-0 group-hover:opacity-100 group-focus:visible group-focus:translate-y-0 group-focus:opacity-100",
                  tip_align(seg, @start, @span)
                ]}
              >
                <div class="text-xs font-semibold tabular-nums text-base-content/60">
                  {Duration.clock(Integer.mod(seg.from, 1440))} – {Duration.clock(
                    Integer.mod(seg.to, 1440)
                  )}
                </div>
                <ul class="mt-1.5 space-y-1">
                  <li
                    :for={e <- seg.dishes}
                    class="flex items-baseline justify-between gap-4 text-sm"
                  >
                    <span class="font-medium">{e.dish.name}</span>
                    <span :if={row.capacity > 1} class="text-xs text-base-content/50">
                      {share_label(e.dish.oven_share)}
                    </span>
                  </li>
                </ul>
                <div :if={row.capacity > 1} class="mt-2 border-t border-base-300 pt-1.5 text-xs">
                  <span class={load_text(%{row | peak: seg.used})}>
                    {seg.used}/{row.capacity} twelfths · {round(seg.used / row.capacity * 100)}% full
                  </span>
                </div>
              </div>
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

  defp height(seg, row), do: min(round(seg.used / row.capacity * 100), 100) |> max(12)

  defp ratio(seg, row), do: seg.used / row.capacity

  defp load_color(%{capacity: 1}, _seg), do: "bg-info/60"

  defp load_color(row, seg) do
    r = ratio(seg, row)

    cond do
      r > 1 -> "bg-error"
      r == 1 -> "bg-warning"
      r >= 0.75 -> "bg-warning/50"
      true -> "bg-success/60"
    end
  end

  defp load_summary(%{capacity: 1} = row) do
    "#{length(row.segments)} #{if length(row.segments) == 1, do: "stretch", else: "stretches"} in use"
  end

  defp load_summary(row) do
    cond do
      row.peak > row.capacity -> "Over capacity"
      row.peak == row.capacity -> "Full at peak"
      true -> "Peak #{round(row.peak / row.capacity * 100)}% full"
    end
  end

  defp load_text(%{capacity: 1}), do: "text-base-content/60"

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
  defp tip_align(seg, start, span) do
    mid = (seg.from + seg.to) / 2 - start

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

  # A compact field with its label inside the box, so a dish's inputs fit on one row.
  defp mini(%{type: "select"} = assigns) do
    ~H"""
    <label class={["select select-sm min-w-0", @class, @f.errors != [] && "select-error"]}>
      <.mini_label label={@label} />
      <select id={@f.id} name={@f.name} class="ms-0 min-w-0 flex-1 ps-1.5" {@rest}>
        {Phoenix.HTML.Form.options_for_select(@options, @f.value)}
      </select>
    </label>
    """
  end

  defp mini(assigns) do
    ~H"""
    <div class={["min-w-0", @class]}>
      <label class={["input input-sm w-full", @f.errors != [] && "input-error"]}>
        <.mini_label label={@label} />
        <input
          type={@type}
          id={@f.id}
          name={@f.name}
          value={mini_value(@f.value)}
          autocomplete="off"
          class="min-w-0 flex-1 tabular-nums"
          {@rest}
        />
      </label>
      <.mini_errors f={@f} />
    </div>
    """
  end

  attr :label, :string, required: true

  defp mini_label(assigns) do
    ~H"""
    <span class="label mr-0 shrink-0 px-0 text-[10px] font-semibold uppercase tracking-wide">{@label}</span>
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
    <.mini f={@form[@field]} label={@label} placeholder="1:30" class="w-32" phx-debounce="500" />
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

  attr :entry, :any, required: true
  attr :form, :any, required: true
  attr :kitchen, :list, required: true
  attr :fixes, :list, default: []

  defp dish_card(assigns) do
    assigns = assign(assigns, :dish, assigns.entry.dish)

    ~H"""
    <li
      id={"dish-card-#{@dish.id}"}
      class="pop-in rounded-xl border border-base-300 bg-base-100/90 px-3 py-2.5 shadow-sm backdrop-blur transition hover:shadow-md"
    >
      <.form for={@form} id={@form.id <> "-form"} phx-change="update">
        <input type="hidden" name="meal_dish_id" value={@dish.id} />

        <%!-- row 1: what it is, when it happens, where it goes --%>
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5">
          <div class="flex min-w-0 flex-1 basis-52 items-center gap-2">
            <span
              class="grid size-7 shrink-0 place-items-center rounded-lg bg-base-200 text-base-content/70"
              title={method_label(@dish.method)}
            >
              <.icon name={method_icon(@dish.method)} class="size-4" />
            </span>
            <input
              type="text"
              id={@form[:name].id}
              name={@form[:name].name}
              value={@form[:name].value}
              aria-label="Name"
              phx-debounce="400"
              class={[
                "input input-ghost input-sm -ml-1 min-w-0 flex-1 px-2 text-base font-semibold",
                @form[:name].errors != [] && "input-error"
              ]}
            />
          </div>

          <.timeline entry={@entry} />

          <span :if={@entry.resource} class="badge badge-secondary badge-soft badge-sm gap-1">
            {@entry.resource.name}
            <span :if={@entry.source == :suggested} class="opacity-60">· auto</span>
          </span>

          <div class="ml-auto flex items-center">
            <.link
              id={"view-dish-#{@dish.id}"}
              navigate={~p"/meals/#{@dish.meal_id}/dishes/#{@dish.id}"}
              class="btn btn-xs btn-circle btn-ghost"
              aria-label={"Details and ingredients for #{@dish.name}"}
              title="Details & ingredients"
            >
              <.icon name="hero-eye" class="size-4" />
            </.link>
            <button
              type="button"
              class="btn btn-xs btn-circle btn-ghost"
              phx-click={JS.toggle(to: "#more-#{@dish.id}", display: "grid")}
              aria-label={"More about #{@dish.name}"}
              title="Notes, link & checklist"
            >
              <.icon name="hero-ellipsis-horizontal" class="size-4" />
            </button>
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

        <%!-- row 2: the inputs; times first, then heat and space --%>
        <div class="mt-2 flex flex-wrap items-start gap-1.5">
          <.duration_input form={@form} field={:prep_minutes} label="Prep" />
          <.duration_input form={@form} field={:cook_minutes} label="Cook" />
          <.duration_input form={@form} field={:rest_minutes} label="Rest" />
          <.mini
            f={@form[:serve_offset_minutes]}
            label="Serve"
            type="select"
            class="w-48"
            options={serve_options(@dish.serve_offset_minutes)}
          />
          <.mini
            :if={@dish.prep_minutes > 0}
            f={@form[:prep_day]}
            label="Prep"
            type="select"
            class="w-48"
            options={MealDish.prep_day_options()}
          />
          <span class="hidden h-8 w-px self-center bg-base-300 sm:mx-1 sm:block" aria-hidden="true"></span>
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
              options={CookingScheduler.Meals.MealDish.oven_share_options()}
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
            label="Appliance"
            type="select"
            class="w-48"
            options={appliance_options(@kitchen)}
          />
        </div>

        <div :if={@entry.issues != []} class="mt-1.5 flex flex-wrap items-center gap-1.5">
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

        <div
          id={"more-#{@dish.id}"}
          style="display: none"
          class="mt-3 grid gap-x-4 gap-y-2 border-t border-base-300 pt-3 sm:grid-cols-2"
        >
          <.input field={@form[:notes]} type="textarea" rows="2" label="Notes" phx-debounce="400" />
          <div>
            <.input
              field={@form[:link]}
              type="text"
              label="Recipe link"
              placeholder="https://…"
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
      </.form>
    </li>
    """
  end

  attr :tab, :atom, required: true
  attr :meal, Meal, required: true
  attr :saved, :list, required: true
  attr :query, :string, required: true
  attr :socket, Phoenix.LiveView.Socket, required: true
  attr :other_meals, :list, required: true
  attr :from_meal, :any, default: nil
  attr :entries, :list, required: true

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
          <%= if @tab == :pick do %>
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
                  phx-click="add_saved"
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
                      {Duration.format(s.cook_minutes)} cook<span :if={s.tags != []}>
                        · {Enum.join(s.tags, ", ")}
                      </span>
                    </span>
                  </span>
                  <span class="btn btn-xs btn-primary btn-soft rounded-full opacity-70 transition group-hover:opacity-100">
                    <.icon name="hero-plus-micro" class="size-3.5" /> Add
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
      />

      <div
        :if={@entries == []}
        class="pop-in mt-6 rounded-3xl border border-dashed border-base-300 bg-base-100/70 p-8 text-center"
      >
        <p class="text-base-content/60">No dishes in this meal yet. Add one above, or:</p>
        <div class="mt-4 flex flex-wrap items-center justify-center gap-2">
          <button
            :for={m <- @other_meals}
            class="btn btn-primary btn-soft rounded-full"
            phx-click="copy_from"
            phx-value-id={m.id}
          >
            <.icon name="hero-document-duplicate" class="size-4" /> Copy from {m.name}
          </button>
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

      <.kitchen_load :if={@load != []} load={@load} serve={@serve} events={@oven_events} />

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
            />
          </ul>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
