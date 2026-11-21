defmodule CookingSchedulerWeb.SummaryLive do
  @moduledoc """
  How a finished meal went: the result, what was planned against what actually happened, notes
  for next time, and pictures of the meal and each dish. Only reachable once the meal is
  complete (ADR 0013, ADR 0024).
  """
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Duration, Kitchen, Meals, Photos, Planner}
  alias CookingScheduler.Meals.Meal
  alias CookingSchedulerWeb.{PhotoGallery, PhotoViewer}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(id)

    if meal.status == :complete do
      if connected?(socket), do: Meals.subscribe(meal)
      {:ok, socket |> assign(:page_title, meal.name) |> assign(:viewer, nil) |> load(meal)}
    else
      {:ok,
       socket
       |> put_flash(:info, "Photos can be added once the meal is finished.")
       |> push_navigate(to: ~p"/meals/#{meal.id}/cook")}
    end
  end

  defp load(socket, %Meal{} = meal) do
    dishes = Meals.list_meal_dishes(meal)
    summary = Meals.summarize(meal, dishes)
    entries = Planner.plan(dishes, Meal.serve_minutes(meal), Kitchen.list_appliances())

    rows =
      for e <- entries, e.dish.cook_minutes > 0 do
        d = e.dish

        %{
          dish: d,
          planned_in: e.cook_at,
          planned_out: e.out_at,
          actual_in: d.cook_started_at,
          actual_out: d.cook_done_at,
          took: d.cook_done_at && Meals.actual_cook(d),
          lateness: Meals.lateness(meal, d),
          form: to_form(%{"next_time" => d.next_time}, as: :dish)
        }
      end
      |> Enum.sort_by(& &1.planned_in)

    socket
    |> assign(:meal, meal)
    |> assign(:delay, summary.delay)
    |> assign(:rows, rows)
    |> assign(:dishes, Enum.filter(dishes, & &1.cook_done_at))
    |> assign(:meal_form, to_form(%{"next_time" => meal.next_time}, as: :meal))
    |> load_photos()
  end

  # Every photo of the meal, its own then each dish's, for the mosaic and the viewer.
  defp load_photos(socket) do
    id = socket.assigns.meal.id
    assign(socket, :photos, Map.get(Photos.by_meal([id]), id, []))
  end

  @impl true
  def handle_info({:meal_updated, _id}, socket),
    do: {:noreply, load(socket, Meals.get_meal!(socket.assigns.meal.id))}

  # A gallery added or removed a photo.
  def handle_info(:photos_changed, socket), do: {:noreply, load_photos(socket)}

  @impl true
  def handle_event("save_meal_notes", %{"meal" => %{"next_time" => text}}, socket) do
    {:ok, meal} = Meals.update_meal(socket.assigns.meal, %{next_time: text})
    {:noreply, assign(socket, :meal, meal)}
  end

  def handle_event(
        "save_dish_notes",
        %{"meal_dish_id" => id, "dish" => %{"next_time" => text}},
        socket
      ) do
    {:ok, _} = id |> Meals.get_meal_dish!() |> Meals.update_meal_dish(%{next_time: text})
    {:noreply, socket}
  end

  # The viewer (ADR 0032), opened from the mosaic (by position) or a gallery (by photo).
  def handle_event("view_photos", %{"index" => index}, socket),
    do: {:noreply, assign(socket, :viewer, %{index: index})}

  def handle_event("view_photo", %{"photo" => id}, socket) do
    socket = load_photos(socket)

    case Enum.find_index(socket.assigns.photos, &(to_string(&1.photo.id) == to_string(id))) do
      nil -> {:noreply, socket}
      index -> {:noreply, assign(socket, :viewer, %{index: index})}
    end
  end

  def handle_event("viewer_" <> _ = event, params, socket) do
    count = length(socket.assigns.photos)
    {:noreply, update(socket, :viewer, &PhotoViewer.handle(event, params, {&1, count}))}
  end

  def handle_event("plan_again", _params, socket) do
    {:ok, meal} = Meals.create_meal_from(socket.assigns.meal, %{}, actual_times: true)
    {:noreply, push_navigate(socket, to: ~p"/meals/#{meal.id}/plan")}
  end

  defp clock(nil), do: "—"
  defp clock(m), do: Duration.clock(Integer.mod(m, 1440))

  defp lateness_label(nil), do: {"not cooked", "text-base-content/40"}
  defp lateness_label(0), do: {"on time", "text-success"}

  defp lateness_label(m) when m > 0,
    do: {"#{Duration.format(m)} late", "font-semibold text-warning"}

  defp lateness_label(m), do: {"#{Duration.format(-m)} early", "text-info"}

  # "7 of 9 on time": timed dishes that were ready by their course (early counts).
  defp on_time(rows), do: Enum.count(rows, &(&1.lateness != nil and &1.lateness <= 0))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        id="summary-back"
        navigate={~p"/"}
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> All meals
      </.link>

      <header class="pop-in flex flex-wrap items-end justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-3xl font-extrabold tracking-tight sm:text-4xl">{@meal.name}</h1>
          <p class="mt-2 flex flex-wrap items-center gap-2 text-sm text-base-content/60">
            <span>{Calendar.strftime(@meal.date, "%A %-d %B %Y")}</span>
            <span
              id="summary-delay"
              class={[
                "inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold",
                (@delay > 0 && "bg-warning text-warning-content") ||
                  "bg-success text-success-content"
              ]}
            >
              <.icon
                name={if @delay > 0, do: "hero-clock-micro", else: "hero-check-circle-micro"}
                class="size-3.5"
              />
              {if @delay > 0, do: "#{Duration.format(@delay)} late", else: "On time"}
            </span>
            <span :if={@rows != []}>{on_time(@rows)} of {length(@rows)} dishes on time</span>
            <span :if={@photos != []}>· {length(@photos)} photos</span>
          </p>
        </div>
        <button id="plan-again" class="btn btn-glow rounded-full" phx-click="plan_again">
          <.icon name="hero-arrow-path" class="size-4" /> Plan it again with the real times
        </button>
      </header>

      <PhotoViewer.mosaic
        :if={@photos != []}
        id="summary-mosaic"
        photos={@photos}
        alt={@meal.name}
        big={5}
        open={&JS.push("view_photos", value: %{index: &1})}
        class="pop-in mt-6 aspect-[2/1] rounded-[1.75rem] shadow-xl sm:aspect-[21/8]"
      />

      <%!-- The meal as a whole: its own photos beside what to change next time. --%>
      <section
        id="meal-photos-section"
        class="mt-6 grid gap-4 lg:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)]"
      >
        <div class="glass rounded-[1.75rem] p-4">
          <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
            The table
          </h2>
          <.live_component module={PhotoGallery} id="meal-photos" owner={@meal} />
        </div>
        <div id="next-time" class="glass flex flex-col rounded-[1.75rem] p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
            Next time
          </h2>
          <p class="mb-2 text-xs text-base-content/50">
            Shows on the dishes and when you plan from this meal.
          </p>
          <.form
            for={@meal_form}
            id="meal-notes-form"
            phx-change="save_meal_notes"
            class="flex flex-1 flex-col"
          >
            <textarea
              id="meal-notes"
              name={@meal_form[:next_time].name}
              rows="4"
              placeholder="The whole meal: timing, the table, what to skip…"
              phx-debounce="600"
              aria-label="Notes for next time"
              class="textarea min-h-28 w-full flex-1 rounded-2xl"
            >{@meal_form[:next_time].value}</textarea>
          </.form>
        </div>
      </section>

      <%!-- One card per dish: its photos, how its timing went, and a note for next time. --%>
      <section id="how-it-went" class="mt-10">
        <h2 class="mb-3 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          The dishes
          <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@rows)}</span>
        </h2>
        <p :if={@dishes == []} id="no-cooked-dishes" class="mb-3 text-sm text-base-content/60">
          No dishes were finished, so there's nothing to photograph.
        </p>
        <ul id="dish-photos-section" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <li
            :for={{r, i} <- Enum.with_index(@rows)}
            id={"actuals-#{r.dish.id}"}
            style={"animation-delay: #{min(i, 12) * 40}ms"}
            class="glass pop-in flex flex-col gap-3 rounded-[1.5rem] p-3"
          >
            <div class="flex items-start justify-between gap-2 px-1">
              <h3 class="min-w-0 truncate font-bold">{r.dish.name}</h3>
              <span class={[
                "shrink-0 text-xs",
                elem(lateness_label(r.lateness), 1)
              ]}>
                {elem(lateness_label(r.lateness), 0)}
              </span>
            </div>

            <dl class="grid grid-cols-3 gap-1 text-center text-xs tabular-nums">
              <.timing label="In" actual={clock(r.actual_in)} planned={clock(r.planned_in)} />
              <.timing label="Out" actual={clock(r.actual_out)} planned={clock(r.planned_out)} />
              <.timing
                label="Took"
                actual={if r.took, do: Duration.format(r.took), else: "—"}
                planned={Duration.format(r.dish.cook_minutes)}
              />
            </dl>

            <.live_component
              :if={r.dish.cook_done_at}
              module={PhotoGallery}
              id={"dish-photos-#{r.dish.id}"}
              owner={r.dish}
              compact
            />

            <.form
              for={r.form}
              id={"dish-notes-#{r.dish.id}"}
              phx-change="save_dish_notes"
              class="mt-auto"
            >
              <input type="hidden" name="meal_dish_id" value={r.dish.id} />
              <textarea
                id={r.form[:next_time].id <> "-#{r.dish.id}"}
                name={r.form[:next_time].name}
                rows="2"
                placeholder="Next time: 20 minutes longer, less salt…"
                phx-debounce="600"
                class="textarea textarea-sm w-full rounded-xl"
                aria-label={"Notes for #{r.dish.name} next time"}
              >{r.form[:next_time].value}</textarea>
            </.form>
          </li>
        </ul>
      </section>

      <PhotoViewer.viewer
        :if={@viewer}
        index={@viewer.index}
        photos={@photos}
        title={@meal.name}
        subtitle={Calendar.strftime(@meal.date, "%d %b %Y")}
      />
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :actual, :string, required: true
  attr :planned, :string, required: true

  # One timing, what happened over what was planned (when they differ).
  defp timing(assigns) do
    ~H"""
    <div class="rounded-xl bg-base-content/5 px-2 py-1.5">
      <dt class="text-[10px] font-semibold uppercase tracking-wider text-base-content/50">
        {@label}
      </dt>
      <dd class="font-semibold">{@actual}</dd>
      <dd :if={@planned != @actual} class="text-[11px] text-base-content/50">
        plan {@planned}
      </dd>
    </div>
    """
  end
end
