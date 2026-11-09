defmodule CookingSchedulerWeb.SummaryLive do
  @moduledoc """
  How a finished meal went: the result, what was planned against what actually happened, notes
  for next time, and pictures of the meal and each dish. Only reachable once the meal is
  complete (ADR 0013, ADR 0024).
  """
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Duration, Kitchen, Meals, Planner}
  alias CookingScheduler.Meals.Meal
  alias CookingSchedulerWeb.PhotoGallery

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(id)

    if meal.status == :complete do
      if connected?(socket), do: Meals.subscribe(meal)
      {:ok, socket |> assign(:page_title, meal.name) |> load(meal)}
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
  end

  @impl true
  def handle_info({:meal_updated, _id}, socket),
    do: {:noreply, load(socket, Meals.get_meal!(socket.assigns.meal.id))}

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

      <header class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-3xl font-extrabold tracking-tight sm:text-4xl">{@meal.name}</h1>
          <p class="mt-1 flex flex-wrap items-center gap-x-3 text-base-content/60">
            <span>{Calendar.strftime(@meal.date, "%A %-d %B %Y")}</span>
            <span id="summary-delay" class={@delay > 0 && "font-semibold text-warning"}>
              {if @delay > 0, do: "#{Duration.format(@delay)} late", else: "On time"}
            </span>
          </p>
        </div>
        <button id="plan-again" class="btn btn-glow rounded-full" phx-click="plan_again">
          <.icon name="hero-arrow-path" class="size-4" /> Plan it again with the real times
        </button>
      </header>

      <section id="how-it-went" class="mt-8">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          How it went
        </h2>
        <div class="overflow-x-auto rounded-2xl border border-base-300 bg-base-100/80">
          <table class="table table-sm">
            <thead>
              <tr class="text-xs uppercase tracking-wider text-base-content/50">
                <th>Dish</th>
                <th class="text-right">Planned in</th>
                <th class="text-right">Went in</th>
                <th class="text-right">Planned out</th>
                <th class="text-right">Came out</th>
                <th class="text-right">Took</th>
                <th class="text-right">Result</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @rows} id={"actuals-#{r.dish.id}"} class="tabular-nums">
                <td class="font-medium">{r.dish.name}</td>
                <td class="text-right text-base-content/60">{clock(r.planned_in)}</td>
                <td class="text-right">{clock(r.actual_in)}</td>
                <td class="text-right text-base-content/60">{clock(r.planned_out)}</td>
                <td class="text-right">{clock(r.actual_out)}</td>
                <td class="text-right">
                  <%= if r.took do %>
                    {Duration.format(r.took)}
                    <span :if={r.took != r.dish.cook_minutes} class="text-xs text-base-content/50">
                      (planned {Duration.format(r.dish.cook_minutes)})
                    </span>
                  <% else %>
                    —
                  <% end %>
                </td>
                <td class={["text-right", elem(lateness_label(r.lateness), 1)]}>
                  {elem(lateness_label(r.lateness), 0)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section id="next-time" class="mt-8">
        <h2 class="mb-1 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          Next time
        </h2>
        <p class="mb-3 text-sm text-base-content/60">
          What to change. These notes show on the dishes and when you plan from this meal.
        </p>
        <.form for={@meal_form} id="meal-notes-form" phx-change="save_meal_notes">
          <.input
            field={@meal_form[:next_time]}
            type="textarea"
            rows="3"
            placeholder="The whole meal: timing, the table, what to skip…"
            phx-debounce="600"
            aria-label="Notes for next time"
          />
        </.form>
        <div class="grid gap-3 sm:grid-cols-2">
          <.form
            :for={r <- @rows}
            for={r.form}
            id={"dish-notes-#{r.dish.id}"}
            phx-change="save_dish_notes"
            class="rounded-xl border border-base-300 bg-base-100/80 p-3"
          >
            <input type="hidden" name="meal_dish_id" value={r.dish.id} />
            <div class="mb-1 flex items-baseline justify-between gap-2 text-sm">
              <span class="font-semibold">{r.dish.name}</span>
              <span class={["text-xs", elem(lateness_label(r.lateness), 1)]}>
                {elem(lateness_label(r.lateness), 0)}
              </span>
            </div>
            <textarea
              id={r.form[:next_time].id <> "-#{r.dish.id}"}
              name={r.form[:next_time].name}
              rows="2"
              placeholder="e.g. 20 minutes longer, less salt"
              phx-debounce="600"
              class="textarea textarea-sm w-full"
              aria-label={"Notes for #{r.dish.name} next time"}
            >{r.form[:next_time].value}</textarea>
          </.form>
        </div>
      </section>

      <section id="meal-photos-section" class="mt-10">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          The meal
        </h2>
        <.live_component module={PhotoGallery} id="meal-photos" owner={@meal} />
      </section>

      <section id="dish-photos-section" class="mt-10">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          The dishes
        </h2>
        <p :if={@dishes == []} id="no-cooked-dishes" class="text-sm text-base-content/60">
          No dishes were finished, so there's nothing to photograph.
        </p>
        <div class="grid gap-8">
          <div :for={dish <- @dishes} id={"dish-#{dish.id}"}>
            <h3 class="mb-2 font-bold">{dish.name}</h3>
            <.live_component module={PhotoGallery} id={"dish-photos-#{dish.id}"} owner={dish} />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
