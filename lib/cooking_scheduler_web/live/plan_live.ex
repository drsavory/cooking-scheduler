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

    socket
    |> assign(:entries, entries)
    |> assign(:load, Planner.load(entries, kitchen))
    |> assign(:serve, serve)
  end

  @impl true
  def handle_event("add_meal_dish", %{"method" => method}, socket) do
    method = Enum.find(MealDish.methods(), &(Atom.to_string(&1) == method))

    if method,
      do: {:ok, _} = Meals.add_meal_dish(socket.assigns.meal, method, socket.assigns.kitchen)

    {:noreply, load(socket)}
  end

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
        {:noreply, load(socket)}

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

  defp form_id(%MealDish{id: id}), do: "dish-#{id}"

  defp card_form(%MealDish{} = d, invalid) do
    Map.get(invalid, d.id) || to_form(Meals.change_meal_dish(d), id: form_id(d))
  end

  defp oven_options(kitchen),
    do: [{"Choose for me", ""} | for(o <- kitchen, o.kind == :oven, do: {o.name, o.id})]

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
  attr :rest, :global, include: ~w(placeholder step min)

  # A compact labelled field, used for the dense per-dish row.
  defp mini(%{type: "select"} = assigns) do
    ~H"""
    <label class="block min-w-0">
      <.mini_label label={@label} />
      <select
        id={@f.id}
        name={@f.name}
        class={["select select-sm w-full", @f.errors != [] && "select-error"]}
        {@rest}
      >
        {Phoenix.HTML.Form.options_for_select(@options, @f.value)}
      </select>
    </label>
    """
  end

  defp mini(assigns) do
    ~H"""
    <label class="block min-w-0">
      <.mini_label label={@label} />
      <input
        type={@type}
        id={@f.id}
        name={@f.name}
        value={mini_value(@f.value)}
        autocomplete="off"
        class={["input input-sm w-full", @f.errors != [] && "input-error"]}
        {@rest}
      />
      <.mini_errors f={@f} />
    </label>
    """
  end

  attr :label, :string, required: true

  defp mini_label(assigns) do
    ~H"""
    <span class="mb-0.5 block text-[11px] font-medium uppercase tracking-wide text-base-content/50">
      {@label}
    </span>
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
    <.mini f={@form[@field]} label={@label} placeholder="1:30" phx-debounce="500" />
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

  defp dish_card(assigns) do
    assigns = assign(assigns, :dish, assigns.entry.dish)

    ~H"""
    <li
      id={"dish-card-#{@dish.id}"}
      class="pop-in rounded-2xl border border-base-300 bg-base-100/90 p-4 shadow-sm backdrop-blur transition hover:shadow-md"
    >
      <.form for={@form} id={@form.id <> "-form"} phx-change="update">
        <input type="hidden" name="meal_dish_id" value={@dish.id} />

        <div class="grid gap-x-6 gap-y-3 lg:grid-cols-[minmax(15rem,21rem)_1fr]">
          <%!-- left: what it is and when it happens --%>
          <div class="min-w-0 space-y-2.5">
            <div class="flex items-center gap-2">
              <span
                class="grid size-8 shrink-0 place-items-center rounded-lg bg-base-200 text-base-content/70"
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
                  "input input-ghost input-sm min-w-0 flex-1 text-base font-semibold",
                  @form[:name].errors != [] && "input-error"
                ]}
              />
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

            <.timeline entry={@entry} />

            <div class="flex flex-wrap items-center gap-1.5">
              <span :if={@entry.resource} class="badge badge-secondary badge-soft badge-sm gap-1">
                {@entry.resource.name}
                <span :if={@entry.source == :suggested} class="opacity-60">· auto</span>
              </span>
              <span
                :for={issue <- @entry.issues}
                class="badge badge-warning badge-soft h-auto gap-1 whitespace-normal py-0.5 text-left"
              >
                <.icon name="hero-exclamation-triangle-micro" class="size-3.5 shrink-0" /> {issue}
              </span>
            </div>
          </div>

          <%!-- right: the inputs --%>
          <div class="grid grid-cols-2 content-start gap-x-3 gap-y-2 sm:grid-cols-4">
            <%= if @dish.method == :oven do %>
              <.mini f={@form[:temp]} label="Temp" type="number" step="any" phx-debounce="500" />
              <.mini
                f={@form[:temp_unit]}
                label="Scale"
                type="select"
                options={[{"Gas mark", :gas_mark}, {"°C", :celsius}, {"°F", :fahrenheit}]}
              />
              <.mini
                f={@form[:oven_share]}
                label="Space"
                type="select"
                options={CookingScheduler.Meals.MealDish.oven_share_options()}
              />
              <div class="col-span-2">
                <.mini
                  f={@form[:appliance_id]}
                  label="Oven"
                  type="select"
                  options={oven_options(@kitchen)}
                />
              </div>
            <% end %>
            <%= if @dish.method == :ring do %>
              <div class="col-span-2">
                <.mini
                  f={@form[:ring_size]}
                  label="Ring"
                  type="select"
                  options={[{"Small", :small}, {"Medium", :medium}, {"Large", :large}]}
                />
              </div>
              <div class="hidden sm:col-span-2 sm:block"></div>
            <% end %>
            <%= if @dish.method == :appliance do %>
              <div class="col-span-2">
                <.mini
                  f={@form[:appliance_id]}
                  label="Appliance"
                  type="select"
                  options={appliance_options(@kitchen)}
                />
              </div>
              <div class="hidden sm:col-span-2 sm:block"></div>
            <% end %>
            <.duration_input form={@form} field={:prep_minutes} label="Prep" />
            <.duration_input form={@form} field={:cook_minutes} label="Cook" />
            <.duration_input form={@form} field={:rest_minutes} label="Rest" />
          </div>
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

      <div id="add-dish" class="mt-5 flex flex-wrap items-center gap-2">
        <button
          :for={
            {method, label} <- [
              oven: "Oven dish",
              ring: "Hob dish",
              appliance: "Slow cooker / grill dish"
            ]
          }
          class="btn btn-sm rounded-full"
          phx-click="add_meal_dish"
          phx-value-method={method}
        >
          <.icon name="hero-plus" class="size-4" /> {label}
        </button>
        <button
          :if={@saved != []}
          id="open-saved"
          class="btn btn-sm btn-secondary btn-soft rounded-full"
          phx-click={JS.toggle(to: "#saved-picker")}
        >
          <.icon name="hero-bookmark" class="size-4" /> From saved dishes ({length(@saved)})
        </button>
      </div>

      <div
        :if={@saved != []}
        id="saved-picker"
        style="display: none"
        class="mt-3 flex flex-wrap gap-2 rounded-2xl border border-base-300 bg-base-100/80 p-3"
      >
        <button
          :for={s <- @saved}
          class="btn btn-xs rounded-full"
          phx-click="add_saved"
          phx-value-id={s.id}
        >
          <.icon name="hero-plus-micro" class="size-3.5" /> {s.name}
        </button>
      </div>

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

      <.kitchen_load :if={@load != []} load={@load} serve={@serve} />

      <ul :if={@entries != []} id="dishes" class="mt-5 grid gap-2.5">
        <.dish_card
          :for={e <- Enum.sort_by(@entries, & &1.dish.id)}
          entry={e}
          form={card_form(e.dish, @invalid)}
          kitchen={@kitchen}
        />
      </ul>
    </Layouts.app>
    """
  end
end
