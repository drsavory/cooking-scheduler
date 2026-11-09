defmodule CookingSchedulerWeb.HomeLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Dates, Duration, Kitchen, Meals}

  @impl true
  def mount(_params, _session, socket) do
    case Kitchen.list_appliances() do
      # Nothing set up yet: this is a first visit, so start with setup.
      [] ->
        {:ok, push_navigate(socket, to: ~p"/setup")}

      _appliances ->
        {:ok,
         socket
         |> assign(:page_title, "Home")
         |> load_meals()}
    end
  end

  defp load_meals(socket) do
    saved = Meals.list_dishes()
    meals = Meals.list_meal_summaries()

    socket
    |> assign(:meals, meals)
    |> assign(:next, next_up(meals))
    |> assign(:saved, saved)
    |> assign(:tags, saved |> Enum.flat_map(& &1.tags) |> Enum.frequencies() |> Enum.sort())
    |> assign_new(:tag, fn -> nil end)
    |> assign(:usage, Meals.usage_by_dish())
    |> assign(
      :new_meal,
      to_form(%{"name" => "", "date" => Date.to_iso8601(Date.utc_today()), "serve_at" => "13:30"},
        as: :meal
      )
    )
  end

  # The meal to get on with (ADR 0025): the soonest unfinished one on or after today, or
  # failing that the most recent unfinished one.
  defp next_up(meals) do
    today = Date.utc_today()
    open = Enum.reject(meals, &(&1.status == :complete))

    case Enum.filter(open, &(Date.compare(&1.meal.date, today) != :lt)) do
      [] -> List.first(open)
      coming -> Enum.min_by(coming, &{Date.to_erl(&1.meal.date), &1.meal.id})
    end
  end

  # What a library dish taught us last time it was cooked.
  defp last_cooked(usage, dish_id) do
    usage
    |> Map.get(dish_id, [])
    |> Enum.find_value(fn {meal, md} ->
      (meal.status == :complete and md.cook_done_at) &&
        %{meal: meal, dish: md, lateness: Meals.lateness(meal, md)}
    end)
  end

  defp lateness_label(0), do: "on time"
  defp lateness_label(m) when m > 0, do: "ran #{Duration.format(m)} over"
  defp lateness_label(m), do: "#{Duration.format(-m)} early"

  @impl true
  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    # Tapping the active tag again clears the filter.
    tag = if tag in ["", socket.assigns.tag], do: nil, else: tag
    {:noreply, assign(socket, :tag, tag)}
  end

  def handle_event("new_meal", %{"from" => from} = params, socket) do
    attrs =
      params
      |> Map.get("meal", %{})
      |> Map.take(["name", "date", "serve_at"])
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> Map.new()

    result =
      case from do
        "" ->
          Meals.create_meal(Map.put_new(attrs, "name", "New meal"))

        id ->
          id
          |> Meals.get_meal!()
          |> Meals.create_meal_from(attrs, actual_times: params["actual_times"] == "true")
      end

    case result do
      {:ok, meal} ->
        {:noreply, push_navigate(socket, to: ~p"/meals/#{meal.id}/plan")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Check the meal's name, date and time")}
    end
  end

  def handle_event("delete_meal", %{"id" => id}, socket) do
    {:ok, _} = id |> Meals.get_meal!() |> Meals.delete_meal()
    {:noreply, load_meals(socket)}
  end

  def handle_event("finish_meal", %{"id" => id}, socket) do
    {:ok, _} = id |> Meals.get_meal!() |> Meals.finish_meal()
    {:noreply, load_meals(socket)}
  end

  def handle_event("start_prepping", %{"id" => id}, socket) do
    meal = Meals.get_meal!(id)
    {:ok, _} = Meals.set_prep_status(meal, :prepping)
    {:noreply, push_navigate(socket, to: ~p"/meals/#{meal.id}/prep")}
  end

  def handle_event("set_meal_status", %{"id" => id, "status" => status}, socket)
      when status in ["planning", "prepping"] do
    {:ok, _} = id |> Meals.get_meal!() |> Meals.set_prep_status(String.to_existing_atom(status))
    {:noreply, load_meals(socket)}
  end

  def handle_event("reset_meal", %{"id" => id}, socket) do
    :ok = id |> Meals.get_meal!() |> Meals.reset_cooking()
    {:noreply, load_meals(socket)}
  end

  def handle_event("delete_dish", %{"id" => id}, socket) do
    {:ok, _} = id |> Meals.get_dish!() |> Meals.delete_dish()
    {:noreply, load_meals(socket)}
  end

  defp date_label(date), do: Calendar.strftime(date, "%d %b %Y")

  defp method_icon(:oven), do: "hero-fire"
  defp method_icon(:ring), do: "hero-stop-circle"
  defp method_icon(:appliance), do: "hero-bolt"

  defp method_gradient(:oven), do: "from-orange-400 to-rose-500"
  defp method_gradient(:ring), do: "from-emerald-400 to-teal-500"
  defp method_gradient(:appliance), do: "from-amber-300 to-yellow-500"

  defp stagger(i), do: "animation-delay: #{min(i, 12) * 45}ms"

  defp plural(1, one, _many), do: "1 #{one}"
  defp plural(n, _one, many), do: "#{n} #{many}"

  attr :status, :atom, required: true
  attr :delay, :integer, default: nil

  defp status_pill(assigns) do
    {label, tone} =
      case {assigns.status, assigns.delay} do
        {:planning, _} -> {"Planning", "text-base-content/70 bg-base-content/10"}
        {:prepping, _} -> {"Prepping", "text-info-content bg-info"}
        {:cooking, _} -> {"Cooking now", "text-warning-content bg-warning"}
        {:complete, 0} -> {"Complete · on time", "text-success-content bg-success"}
        {:complete, d} -> {"#{Duration.format(d)} late", "text-warning-content bg-warning"}
      end

    assigns = assign(assigns, label: label, tone: tone)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold",
      @tone
    ]}>
      <span class={["size-1.5 rounded-full bg-current", @status == :cooking && "dot-live"]}></span>
      {@label}
    </span>
    """
  end

  attr :date, Date, required: true

  defp date_tile(assigns) do
    ~H"""
    <div class="grid size-16 shrink-0 place-items-center rounded-2xl bg-gradient-to-br from-primary to-accent text-primary-content shadow-lg shadow-primary/25">
      <div class="text-center leading-none">
        <div class="text-[10px] font-bold uppercase tracking-widest opacity-80">
          {Calendar.strftime(@date, "%b")}
        </div>
        <div class="mt-1 text-2xl font-extrabold tabular-nums">{@date.day}</div>
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :value, :any, required: true

  defp chip(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded-full bg-base-content/5 px-2.5 py-1 text-xs font-medium text-base-content/70">
      <.icon name={@icon} class="size-3.5" /> {@value}
    </span>
    """
  end

  defp visible(saved, nil), do: saved
  defp visible(saved, tag), do: Enum.filter(saved, &(tag in &1.tags))

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown, visible(assigns.saved, assigns.tag))

    ~H"""
    <Layouts.app flash={@flash}>
      <section class="pop-in">
        <p class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/50">
          Cooking scheduler
        </p>
        <h1 class="mt-2 text-5xl font-extrabold tracking-tight sm:text-6xl">
          What are we <span class="gradient-text">cooking</span>?
        </h1>

        <div
          :if={@next}
          id="next-up"
          class="pop-in mt-6 flex flex-wrap items-center gap-x-6 gap-y-3 rounded-[1.75rem] bg-gradient-to-br from-primary via-primary to-secondary p-5 text-primary-content shadow-lg shadow-primary/20"
        >
          <.date_tile date={@next.meal.date} />
          <div class="min-w-0 flex-1 basis-56">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary-content/70">
              Next up · {Dates.relative(@next.meal.date)}
            </p>
            <h2 class="truncate text-2xl font-extrabold tracking-tight">{@next.meal.name}</h2>
            <p class="text-sm text-primary-content/80">
              Dinner at {Calendar.strftime(@next.meal.serve_at, "%H:%M")} · {plural(
                @next.dishes,
                "dish",
                "dishes"
              )}
              <span :if={@next.meal.next_time not in [nil, ""]}>· {@next.meal.next_time}</span>
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <%= case @next.status do %>
              <% :planning -> %>
                <.link
                  id="next-plan"
                  navigate={~p"/meals/#{@next.meal.id}/plan"}
                  class="btn rounded-full border-0 bg-white text-primary shadow hover:bg-white/90"
                >
                  <.icon name="hero-table-cells" class="size-4" /> Keep planning
                </.link>
                <button
                  id="next-prep"
                  phx-click={JS.push("start_prepping", value: %{id: @next.meal.id})}
                  class="btn btn-ghost rounded-full text-primary-content hover:bg-white/20"
                >
                  <.icon name="hero-shopping-bag-micro" class="size-4" /> Start prepping
                </button>
              <% :prepping -> %>
                <.link
                  id="next-prep"
                  navigate={~p"/meals/#{@next.meal.id}/prep"}
                  class="btn rounded-full border-0 bg-white text-primary shadow hover:bg-white/90"
                >
                  <.icon name="hero-clipboard-document-check" class="size-4" /> Open prep
                </.link>
                <.link
                  id="next-cook"
                  navigate={~p"/meals/#{@next.meal.id}/cook"}
                  class="btn btn-ghost rounded-full text-primary-content hover:bg-white/20"
                >
                  <.icon name="hero-play-solid" class="size-4" /> Cook
                </.link>
              <% _ -> %>
                <.link
                  id="next-cook"
                  navigate={~p"/meals/#{@next.meal.id}/cook"}
                  class="btn rounded-full border-0 bg-white text-primary shadow hover:bg-white/90"
                >
                  <.icon name="hero-play-solid" class="size-4" /> Back to cooking
                </.link>
            <% end %>
          </div>
        </div>

        <form
          id="new-meal-form"
          phx-submit="new_meal"
          class="glass mt-6 grid gap-3 rounded-[1.75rem] p-4"
        >
          <div class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_10rem_7rem]">
            <input
              type="text"
              id="new-meal-name"
              name="meal[name]"
              value={@new_meal[:name].value}
              placeholder="Name the meal, e.g. Christmas 2026"
              aria-label="Meal name"
              maxlength="80"
              class="input h-12 w-full rounded-full border-0 bg-base-200 px-5 text-base"
            />
            <input
              type="date"
              id="new-meal-date"
              name="meal[date]"
              value={@new_meal[:date].value}
              aria-label="Date"
              class="input h-12 w-full rounded-full border-0 bg-base-200 px-4"
            />
            <input
              type="time"
              id="new-meal-time"
              name="meal[serve_at]"
              value={@new_meal[:serve_at].value}
              aria-label="Dinner time"
              class="input h-12 w-full rounded-full border-0 bg-base-200 px-4 text-center"
            />
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <div class="relative min-w-0 flex-1 basis-64">
              <.icon
                name="hero-document-duplicate"
                class="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-base-content/50"
              />
              <select
                id="new-meal-from"
                name="from"
                aria-label="Start from"
                class="select h-12 w-full rounded-full border-0 bg-base-200 pl-11 text-base text-base-content"
              >
                <option value="" class="bg-base-100 text-base-content">Start from scratch</option>
                <option :for={%{meal: m} <- @meals} value={m.id} class="bg-base-100 text-base-content">
                  Start from {m.name} ({date_label(m.date)})
                </option>
              </select>
            </div>
            <label
              :if={Enum.any?(@meals, &(&1.status == :complete))}
              class="flex cursor-pointer items-center gap-2 text-sm"
              title="For a meal you've cooked: each dish starts with how long it really took"
            >
              <input type="hidden" name="actual_times" value="false" />
              <input
                id="new-meal-actual"
                type="checkbox"
                name="actual_times"
                value="true"
                class="checkbox checkbox-sm"
              /> Use the times that actually happened
            </label>
            <button
              id="create-meal"
              type="submit"
              class="btn btn-glow h-12 rounded-full px-6 text-base"
            >
              <.icon name="hero-sparkles" class="size-5" /> Create meal
            </button>
            <.link
              id="create-dish"
              navigate={~p"/dishes/new"}
              class="btn btn-glass h-12 rounded-full px-5 text-base"
            >
              <.icon name="hero-plus" class="size-5" /> Create dish
            </.link>
          </div>
        </form>
      </section>

      <section id="meals" class="mt-12">
        <h2 class="mb-4 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          Meals
          <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@meals)}</span>
        </h2>

        <p
          :if={@meals == []}
          class="glass rounded-3xl border-dashed p-10 text-center text-base-content/60"
        >
          <.icon name="hero-cake" class="mx-auto mb-2 size-8 opacity-60" />
          No meals yet. Create one above to start planning.
        </p>

        <ul :if={@meals != []} class="grid gap-4 sm:grid-cols-2">
          <li
            :for={{s, i} <- Enum.with_index(@meals)}
            id={"meal-#{s.meal.id}"}
            style={stagger(i)}
            class="glass glass-lift pop-in group flex flex-col rounded-[1.75rem] p-5"
          >
            <div class="flex items-start gap-4">
              <.date_tile date={s.meal.date} />
              <div class="min-w-0 flex-1">
                <h3 class="truncate text-xl font-bold tracking-tight">{s.meal.name}</h3>
                <p class="mt-0.5 text-sm text-base-content/60">
                  Dinner at {Calendar.strftime(s.meal.serve_at, "%H:%M")}
                </p>
                <div class="mt-2"><.status_pill status={s.status} delay={s.delay} /></div>
              </div>
              <.confirm_button
                id={"delete-meal-#{s.meal.id}"}
                title={"Delete #{s.meal.name}?"}
                message={"This removes the meal and its #{plural(s.dishes, "dish", "dishes")}. This can't be undone."}
                confirm_label="Delete"
                tone={:danger}
                on_confirm={JS.push("delete_meal", value: %{id: s.meal.id})}
                class="btn btn-xs btn-circle btn-ghost opacity-0 transition group-hover:opacity-100 [@media(hover:none)]:opacity-100 hover:text-error focus:opacity-100"
                aria-label={"Delete #{s.meal.name}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </.confirm_button>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <.chip icon="hero-squares-2x2-micro" value={plural(s.dishes, "dish", "dishes")} />
              <.chip
                :if={s.prep_minutes > 0}
                icon="hero-clock-micro"
                value={"#{Duration.format(s.prep_minutes)} prep"}
              />
            </div>

            <div :if={s.status in [:planning, :prepping]} class="mt-4 flex gap-2 text-sm">
              <button
                :if={s.status == :planning}
                id={"start-prepping-#{s.meal.id}"}
                phx-click={JS.push("start_prepping", value: %{id: s.meal.id})}
                class="btn btn-xs btn-ghost rounded-full"
              >
                <.icon name="hero-shopping-bag-micro" class="size-3.5" /> Start prepping
              </button>
              <.link
                :if={s.status == :prepping}
                id={"prep-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/prep"}
                class="btn btn-xs btn-primary btn-soft rounded-full"
              >
                <.icon name="hero-clipboard-document-check-micro" class="size-3.5" /> Open prep
              </.link>
              <button
                :if={s.status == :prepping}
                id={"back-to-planning-#{s.meal.id}"}
                phx-click={JS.push("set_meal_status", value: %{id: s.meal.id, status: "planning"})}
                class="btn btn-xs btn-ghost rounded-full"
              >
                <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> Back to planning
              </button>
            </div>

            <div :if={s.status in [:cooking, :complete]} class="mt-4 flex gap-2 text-sm">
              <.confirm_button
                :if={s.status == :cooking}
                id={"finish-meal-#{s.meal.id}"}
                title="Finish cooking now?"
                message="Dishes that aren't done yet are left out of the result."
                confirm_label="Finish"
                on_confirm={JS.push("finish_meal", value: %{id: s.meal.id})}
                class="btn btn-xs btn-ghost rounded-full"
              >
                <.icon name="hero-flag-micro" class="size-3.5" /> Finish cooking
              </.confirm_button>
              <.confirm_button
                id={"reset-meal-#{s.meal.id}"}
                title="Reset cooking progress?"
                message="Started and finished marks are cleared. The plan stays."
                confirm_label="Reset"
                tone={:danger}
                on_confirm={JS.push("reset_meal", value: %{id: s.meal.id})}
                class="btn btn-xs btn-ghost rounded-full"
              >
                <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> Reset progress
              </.confirm_button>
            </div>

            <div class="mt-5 flex gap-2">
              <.link
                id={"plan-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/plan"}
                class="btn btn-glass flex-1 rounded-full"
              >
                <.icon name="hero-table-cells" class="size-4" /> Plan
              </.link>
              <.link
                :if={s.status == :complete}
                id={"summary-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/summary"}
                class="btn btn-glow flex-1 rounded-full"
              >
                <.icon name="hero-camera" class="size-4" /> Photos
              </.link>
              <.link
                :if={s.status != :complete}
                id={"cook-meal-#{s.meal.id}"}
                navigate={~p"/meals/#{s.meal.id}/cook"}
                class="btn btn-glow flex-1 rounded-full"
              >
                <.icon name="hero-play-solid" class="size-4" /> Cook
              </.link>
            </div>
          </li>
        </ul>
      </section>

      <section id="dishes" class="mt-12">
        <h2 class="mb-4 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          Dishes
          <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@saved)}</span>
        </h2>

        <p
          :if={@saved == []}
          class="glass rounded-3xl border-dashed p-10 text-center text-base-content/60"
        >
          <.icon name="hero-beaker" class="mx-auto mb-2 size-8 opacity-60" />
          No dishes yet. Create one, or add dishes while planning a meal.
        </p>

        <div :if={@tags != []} id="tag-filter" class="mb-4 flex flex-wrap gap-2">
          <button
            type="button"
            id="tag-all"
            phx-click="filter_tag"
            phx-value-tag=""
            class={[
              "rounded-full border px-3 py-1 text-sm transition",
              (@tag == nil && "border-primary bg-primary/15 font-semibold text-primary") ||
                "border-base-300 hover:border-primary/50"
            ]}
          >
            All
          </button>
          <button
            :for={{tag, count} <- @tags}
            type="button"
            id={"tag-filter-#{tag}"}
            phx-click="filter_tag"
            phx-value-tag={tag}
            aria-pressed={to_string(@tag == tag)}
            class={[
              "rounded-full border px-3 py-1 text-sm capitalize transition",
              (@tag == tag && "border-primary bg-primary/15 font-semibold text-primary") ||
                "border-base-300 hover:border-primary/50"
            ]}
          >
            {tag} <span class="text-xs opacity-60">{count}</span>
          </button>
        </div>

        <ul :if={@saved != []} class="grid gap-3 sm:grid-cols-2">
          <li
            :for={{d, i} <- Enum.with_index(@shown)}
            id={"dish-#{d.id}"}
            style={stagger(i)}
            class="glass glass-lift pop-in group relative flex items-center gap-3 rounded-2xl p-3 pr-2"
          >
            <span class={[
              "grid size-11 shrink-0 place-items-center rounded-xl bg-gradient-to-br text-white shadow-md",
              method_gradient(d.method)
            ]}>
              <.icon name={method_icon(d.method)} class="size-5" />
            </span>
            <div class="min-w-0 flex-1">
              <.link
                id={"view-dish-#{d.id}"}
                navigate={~p"/dishes/#{d.id}"}
                class="block truncate font-semibold hover:text-primary after:absolute after:inset-0"
              >
                {d.name}
              </.link>
              <div class="text-xs text-base-content/60">
                {Duration.format(d.cook_minutes)} cook · {plural(
                  length(Map.get(@usage, d.id, [])),
                  "meal",
                  "meals"
                )}
              </div>
              <div
                :if={last = last_cooked(@usage, d.id)}
                id={"last-cooked-#{d.id}"}
                class="mt-0.5 text-xs text-base-content/60"
              >
                Last cooked {last.meal.name} ·
                <span class={[
                  last.lateness > 0 && "text-warning",
                  last.lateness == 0 && "text-success"
                ]}>
                  {lateness_label(last.lateness)}
                </span>
                <span :if={last.dish.next_time not in [nil, ""]} class="line-clamp-1 italic">
                  “{last.dish.next_time}”
                </span>
              </div>
              <div :if={d.tags != []} id={"dish-tags-#{d.id}"} class="mt-1 flex flex-wrap gap-1">
                <span
                  :for={tag <- d.tags}
                  class="rounded-full bg-base-content/10 px-2 py-0.5 text-[11px] capitalize"
                >
                  {tag}
                </span>
              </div>
            </div>
            <.confirm_button
              id={"delete-dish-#{d.id}"}
              title={"Delete #{d.name}?"}
              message="Meals that already use it keep their copy."
              confirm_label="Delete"
              tone={:danger}
              on_confirm={JS.push("delete_dish", value: %{id: d.id})}
              class="relative z-10 btn btn-xs btn-circle btn-ghost opacity-0 transition group-hover:opacity-100 [@media(hover:none)]:opacity-100 hover:text-error focus:opacity-100"
              aria-label={"Delete #{d.name}"}
            >
              <.icon name="hero-trash" class="size-4" />
            </.confirm_button>
          </li>
        </ul>
      </section>

      <p class="mt-14 text-center text-sm text-base-content/50">
        <.link id="edit-kitchen" navigate={~p"/setup"} class="link link-hover">
          <.icon name="hero-cog-6-tooth-micro" class="size-4" /> Kitchen settings
        </.link>
      </p>
    </Layouts.app>
    """
  end
end
