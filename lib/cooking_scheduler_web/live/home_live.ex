defmodule CookingSchedulerWeb.HomeLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Dates, Duration, Kitchen, Meals, Photos}
  alias CookingSchedulerWeb.PhotoViewer

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
    next = next_up(meals)

    socket
    |> assign(:meals, meals)
    |> assign(:next, next)
    # Unfinished meals other than the one in the hero, soonest first; then the cooked ones.
    |> assign(
      :upcoming,
      meals
      |> Enum.reject(&(&1.status == :complete or (next && &1.meal.id == next.meal.id)))
      |> Enum.sort_by(&{Date.to_erl(&1.meal.date), &1.meal.id})
    )
    |> assign(:past, Enum.filter(meals, &(&1.status == :complete)))
    |> assign(:past_photos, Photos.by_meal(for(m <- meals, m.status == :complete, do: m.meal.id)))
    |> assign_new(:viewer, fn -> nil end)
    |> assign_new(:show_past, fn -> false end)
    |> assign(:saved, saved)
    |> assign(:tags, saved |> Enum.flat_map(& &1.tags) |> Enum.frequencies() |> Enum.sort())
    |> assign_new(:tag, fn -> nil end)
    |> assign_new(:new_from, fn -> "" end)
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

  defp cooked_source?(meals, from),
    do: Enum.any?(meals, &(to_string(&1.meal.id) == from and &1.status == :complete))

  defp lateness_label(0), do: "on time"
  defp lateness_label(m) when m > 0, do: "ran #{Duration.format(m)} over"
  defp lateness_label(m), do: "#{Duration.format(-m)} early"

  @impl true
  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    # Tapping the active tag again clears the filter.
    tag = if tag in ["", socket.assigns.tag], do: nil, else: tag
    {:noreply, assign(socket, :tag, tag)}
  end

  # The "real times" option only means something for a meal that has been cooked.
  def handle_event("new_meal_change", params, socket) do
    socket = assign(socket, :new_from, params["from"] || "")

    case params do
      %{"meal" => meal} -> {:noreply, assign(socket, :new_meal, to_form(meal, as: :meal))}
      _ -> {:noreply, socket}
    end
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

  # The photo viewer (ADR 0032): one past meal's photos, one at a time, wrapping round.
  def handle_event("view_photos", %{"meal" => meal_id, "index" => index}, socket) do
    meal_id = String.to_integer(to_string(meal_id))
    index = String.to_integer(to_string(index))

    if Map.get(socket.assigns.past_photos, meal_id, []) == [],
      do: {:noreply, socket},
      else: {:noreply, assign(socket, :viewer, %{meal_id: meal_id, index: index})}
  end

  def handle_event("viewer_" <> _ = event, params, socket) do
    count =
      case socket.assigns.viewer do
        %{meal_id: id} -> length(Map.get(socket.assigns.past_photos, id, []))
        nil -> 0
      end

    {:noreply, update(socket, :viewer, &PhotoViewer.handle(event, params, {&1, count}))}
  end

  def handle_event("toggle_past", _params, socket),
    do: {:noreply, update(socket, :show_past, &(!&1))}

  # A new meal with this one's dishes, dated today; optionally with how long things really took.
  def handle_event("plan_again", %{"id" => id} = params, socket) do
    {:ok, meal} =
      id
      |> Meals.get_meal!()
      |> Meals.create_meal_from(%{}, actual_times: params["actual"] == "true")

    {:noreply, push_navigate(socket, to: ~p"/meals/#{meal.id}/plan")}
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
  attr :small, :boolean, default: false

  defp date_tile(assigns) do
    ~H"""
    <div class={[
      "grid shrink-0 place-items-center bg-gradient-to-br from-primary to-accent text-primary-content shadow-lg shadow-primary/25",
      (@small && "size-12 rounded-xl") || "size-16 rounded-2xl"
    ]}>
      <div class="text-center leading-none">
        <div class="text-[10px] font-bold uppercase tracking-widest opacity-80">
          {Calendar.strftime(@date, "%b")}
        </div>
        <div class={["mt-1 font-extrabold tabular-nums", (@small && "text-lg") || "text-2xl"]}>
          {@date.day}
        </div>
      </div>
    </div>
    """
  end

  defp viewed_meal(past, %{meal_id: id}),
    do: Enum.find_value(past, &(&1.meal.id == id && &1.meal))

  # Where a meal's main action goes, by stage: plan, prep, cook, or how it went.
  defp stage_path(%{meal: m, status: :planning}), do: ~p"/meals/#{m.id}/plan"
  defp stage_path(%{meal: m, status: :prepping}), do: ~p"/meals/#{m.id}/prep"
  defp stage_path(%{meal: m, status: :cooking}), do: ~p"/meals/#{m.id}/cook"
  defp stage_path(%{meal: m, status: :complete}), do: ~p"/meals/#{m.id}/summary"

  attr :summary, :map, required: true
  attr :photos, :list, required: true
  attr :index, :integer, required: true

  # A cooked meal, led by its photos: a mosaic that opens the viewer, then what happened.
  defp past_meal(assigns) do
    assigns = assign(assigns, meal: assigns.summary.meal, count: length(assigns.photos))

    ~H"""
    <li
      id={"meal-#{@meal.id}"}
      style={stagger(@index)}
      class="glass glass-lift pop-in group/card relative flex flex-col rounded-[1.75rem] focus-within:z-20 has-[[role=menu]:not(.hidden)]:z-20"
    >
      <%= if @count == 0 do %>
        <.link
          id={"meal-photos-empty-#{@meal.id}"}
          navigate={~p"/meals/#{@meal.id}/summary"}
          class="m-2 flex aspect-[4/3] flex-col items-center justify-center gap-1 rounded-[1.4rem] border-2 border-dashed border-base-content/15 text-sm text-base-content/50 transition hover:border-primary/50 hover:text-primary"
        >
          <.icon name="hero-camera" class="size-7" /> Add photos
        </.link>
      <% else %>
        <PhotoViewer.mosaic
          id={"meal-photo-#{@meal.id}"}
          photos={@photos}
          alt={@meal.name}
          open={&JS.push("view_photos", value: %{meal: @meal.id, index: &1})}
          class="m-2 aspect-[4/3] rounded-[1.4rem]"
        />
      <% end %>

      <div class="flex items-center gap-3 px-4 pb-4 pt-2">
        <div class="min-w-0 flex-1">
          <.link
            navigate={~p"/meals/#{@meal.id}/summary"}
            class="block truncate font-bold tracking-tight transition hover:text-primary"
          >
            {@meal.name}
          </.link>
          <p class="flex flex-wrap items-center gap-x-2 text-xs text-base-content/60">
            <span>{Calendar.strftime(@meal.date, "%d %b %Y")}</span>
            <span class={[
              "inline-flex items-center gap-0.5 font-semibold",
              @summary.delay == 0 && "text-success",
              (@summary.delay || 0) > 0 && "text-warning"
            ]}>
              <.icon
                name={if @summary.delay == 0, do: "hero-check-circle-micro", else: "hero-clock-micro"}
                class="size-3.5"
              />
              {if @summary.delay == 0,
                do: "On time",
                else: "#{Duration.format(@summary.delay || 0)} late"}
            </span>
            <span>{plural(@summary.dishes, "dish", "dishes")}</span>
            <span :if={@count > 0}>{plural(@count, "photo", "photos")}</span>
          </p>
        </div>
        <.stage_button summary={@summary} />
        <.meal_menu summary={@summary} />
      </div>
    </li>
    """
  end

  attr :summary, :map, required: true

  # The one button a meal row gets: the thing to do next at its stage.
  defp stage_button(assigns) do
    {id, icon, label, class} =
      case assigns.summary.status do
        :planning -> {"plan-meal", "hero-table-cells-micro", "Plan", "btn-glass"}
        :prepping -> {"prep-meal", "hero-clipboard-document-check-micro", "Prep", "btn-glass"}
        :cooking -> {"cook-meal", "hero-play-solid", "Cook", "btn-primary"}
        :complete -> {"summary-meal", "hero-chart-bar-micro", "How it went", "btn-ghost"}
      end

    assigns = assign(assigns, id: id, icon: icon, label: label, class: class)

    ~H"""
    <.link
      id={"#{@id}-#{@summary.meal.id}"}
      navigate={stage_path(@summary)}
      class={["btn btn-sm shrink-0 rounded-full", @class]}
    >
      <.icon name={@icon} class="size-4" />
      <span class="hidden sm:inline">{@label}</span>
    </.link>
    """
  end

  attr :summary, :map, required: true
  attr :class, :string, default: "btn-ghost"

  # Everything else you can do with a meal, out of the way until asked for.
  defp meal_menu(assigns) do
    assigns = assign(assigns, meal: assigns.summary.meal, status: assigns.summary.status)

    ~H"""
    <div class="relative shrink-0">
      <button
        type="button"
        id={"meal-menu-button-#{@meal.id}"}
        aria-haspopup="menu"
        aria-label={"More for #{@meal.name}"}
        phx-click={
          JS.toggle(
            to: "#meal-menu-#{@meal.id}",
            in: {"transition ease-out duration-150", "opacity-0 scale-95", "opacity-100 scale-100"},
            out: {"transition ease-in duration-100", "opacity-100 scale-100", "opacity-0 scale-95"}
          )
        }
        class={["btn btn-sm btn-circle", @class]}
      >
        <.icon name="hero-ellipsis-horizontal" class="size-5" />
      </button>
      <div
        id={"meal-menu-#{@meal.id}"}
        role="menu"
        phx-click-away={JS.hide(to: "#meal-menu-#{@meal.id}")}
        class="glass absolute right-0 top-full z-30 mt-1 hidden w-60 origin-top-right rounded-2xl p-1.5 text-sm text-base-content shadow-xl"
      >
        <%= if @status == :planning do %>
          <.menu_item
            id={"start-prepping-#{@meal.id}"}
            icon="hero-shopping-bag-micro"
            click={JS.push("start_prepping", value: %{id: @meal.id})}
          >
            Start prepping
          </.menu_item>
        <% end %>
        <%= if @status in [:prepping, :cooking] do %>
          <.menu_item
            id={"edit-plan-#{@meal.id}"}
            icon="hero-table-cells-micro"
            navigate={~p"/meals/#{@meal.id}/plan"}
          >
            Edit the plan
          </.menu_item>
        <% end %>
        <%= if @status in [:planning, :prepping] do %>
          <.menu_item
            id={"cook-from-menu-#{@meal.id}"}
            icon="hero-play-micro"
            navigate={~p"/meals/#{@meal.id}/cook"}
          >
            Start cooking
          </.menu_item>
        <% end %>
        <%= if @status == :prepping do %>
          <.menu_item
            id={"back-to-planning-#{@meal.id}"}
            icon="hero-arrow-uturn-left-micro"
            click={JS.push("set_meal_status", value: %{id: @meal.id, status: "planning"})}
          >
            Back to planning
          </.menu_item>
        <% end %>
        <%= if @status == :cooking do %>
          <.confirm_button
            id={"finish-meal-#{@meal.id}"}
            title="Finish cooking now?"
            message="Dishes that aren't done yet are left out of the result."
            confirm_label="Finish"
            on_confirm={JS.push("finish_meal", value: %{id: @meal.id})}
            class={menu_item_class()}
          >
            <.icon name="hero-flag-micro" class="size-4 opacity-60" /> Finish cooking
          </.confirm_button>
        <% end %>
        <%= if @status == :complete do %>
          <.menu_item
            id={"plan-again-#{@meal.id}"}
            icon="hero-document-duplicate-micro"
            click={JS.push("plan_again", value: %{id: @meal.id})}
          >
            Plan it again
          </.menu_item>
          <.menu_item
            id={"plan-again-actual-#{@meal.id}"}
            icon="hero-clock-micro"
            click={JS.push("plan_again", value: %{id: @meal.id, actual: "true"})}
          >
            Plan it again with the real times
          </.menu_item>
        <% end %>
        <%= if @status in [:cooking, :complete] do %>
          <.confirm_button
            id={"reset-meal-#{@meal.id}"}
            title="Reset cooking progress?"
            message="Started and finished marks are cleared. The plan stays."
            confirm_label="Reset"
            tone={:danger}
            on_confirm={JS.push("reset_meal", value: %{id: @meal.id})}
            class={menu_item_class()}
          >
            <.icon name="hero-arrow-path-micro" class="size-4 opacity-60" /> Reset progress
          </.confirm_button>
        <% end %>
        <div class="my-1 h-px bg-base-content/10"></div>
        <.confirm_button
          id={"delete-meal-#{@meal.id}"}
          title={"Delete #{@meal.name}?"}
          message={"This removes the meal and its #{plural(@summary.dishes, "dish", "dishes")}. This can't be undone."}
          confirm_label="Delete"
          tone={:danger}
          on_confirm={JS.push("delete_meal", value: %{id: @meal.id})}
          class={[menu_item_class(), "text-error hover:bg-error/10"]}
        >
          <.icon name="hero-trash-micro" class="size-4" /> Delete meal
        </.confirm_button>
      </div>
    </div>
    """
  end

  defp menu_item_class,
    do:
      "flex w-full items-center gap-2 rounded-xl px-3 py-2 text-left font-medium transition hover:bg-base-content/10"

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :navigate, :string, default: nil
  attr :click, :any, default: nil
  slot :inner_block, required: true

  defp menu_item(%{navigate: nil} = assigns) do
    ~H"""
    <button id={@id} type="button" role="menuitem" phx-click={@click} class={menu_item_class()}>
      <.icon name={@icon} class="size-4 opacity-60" /> {render_slot(@inner_block)}
    </button>
    """
  end

  defp menu_item(assigns) do
    ~H"""
    <.link id={@id} role="menuitem" navigate={@navigate} class={menu_item_class()}>
      <.icon name={@icon} class="size-4 opacity-60" /> {render_slot(@inner_block)}
    </.link>
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

        <%!-- Side by side on wide screens: what's next, and starting a new meal. --%>
        <div class={["mt-6 grid items-stretch gap-4", @next && "lg:grid-cols-2"]}>
          <div
            :if={@next}
            id="next-up"
            class="pop-in relative z-10 flex flex-col gap-4 rounded-[1.75rem] bg-gradient-to-br from-primary via-primary to-secondary p-5 text-primary-content shadow-lg shadow-primary/20"
          >
            <div class="flex items-center gap-4">
              <.date_tile date={@next.meal.date} />
              <div class="min-w-0 flex-1">
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
            </div>
            <div class="mt-auto flex flex-wrap items-center gap-2">
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
              <div class="ml-auto">
                <.meal_menu summary={@next} class="btn-ghost text-primary-content hover:bg-white/20" />
              </div>
            </div>
          </div>

          <form
            id="new-meal-form"
            phx-change="new_meal_change"
            phx-submit="new_meal"
            class="glass grid content-start gap-3 rounded-[1.75rem] p-4"
          >
            <p class="px-1 text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
              Plan a new meal
            </p>
            <div class={[
              "grid gap-3",
              (@next && "sm:grid-cols-[minmax(0,1fr)_7rem]") ||
                "sm:grid-cols-[minmax(0,1fr)_10rem_7rem]"
            ]}>
              <input
                type="text"
                id="new-meal-name"
                name="meal[name]"
                value={@new_meal[:name].value}
                placeholder="Name the meal, e.g. Christmas 2026"
                aria-label="Meal name"
                maxlength="80"
                class={[
                  "input h-12 w-full rounded-full border-0 bg-base-200 px-5 text-base",
                  @next && "sm:col-span-2"
                ]}
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
                  <option
                    :for={%{meal: m} <- @meals}
                    value={m.id}
                    selected={to_string(m.id) == @new_from}
                    class="bg-base-100 text-base-content"
                  >
                    Start from {m.name} ({date_label(m.date)})
                  </option>
                </select>
              </div>
              <label
                :if={cooked_source?(@meals, @new_from)}
                id="new-meal-actual-label"
                class="pop-in flex cursor-pointer items-center gap-2 text-sm"
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
            </div>
          </form>
        </div>
      </section>

      <%!-- Meals (ADR 0031): what's coming up, then a quieter list of what's been cooked. --%>
      <p
        :if={@meals == []}
        id="no-meals"
        class="glass mt-12 rounded-3xl border-dashed p-10 text-center text-base-content/60"
      >
        <.icon name="hero-cake" class="mx-auto mb-2 size-8 opacity-60" />
        No meals yet. Create one above to start planning.
      </p>

      <%!-- Coming up, then the past meals' photos at full width (ADR 0032). --%>
      <div :if={@upcoming != [] or @past != []} class="mt-12 grid gap-12">
        <section :if={@upcoming != []} id="upcoming" class="min-w-0">
          <h2 class="mb-3 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
            Coming up
            <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@upcoming)}</span>
          </h2>
          <ul class="glass divide-y divide-base-content/10 rounded-[1.75rem]">
            <li
              :for={{s, i} <- Enum.with_index(@upcoming)}
              id={"meal-#{s.meal.id}"}
              style={stagger(i)}
              class="pop-in relative flex items-center gap-4 px-4 py-3 first:rounded-t-[1.75rem] last:rounded-b-[1.75rem] focus-within:z-20 has-[[role=menu]:not(.hidden)]:z-20 sm:px-5"
            >
              <.date_tile date={s.meal.date} small />
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                  <.link
                    navigate={stage_path(s)}
                    class="truncate text-lg font-bold tracking-tight transition hover:text-primary"
                  >
                    {s.meal.name}
                  </.link>
                  <.status_pill status={s.status} delay={s.delay} />
                </div>
                <p class="mt-0.5 truncate text-sm text-base-content/60">
                  {Dates.relative(s.meal.date)} · dinner {Calendar.strftime(s.meal.serve_at, "%H:%M")} · {plural(
                    s.dishes,
                    "dish",
                    "dishes"
                  )}<span :if={s.prep_minutes > 0}> · {Duration.format(s.prep_minutes)} prep</span>
                </p>
              </div>
              <.stage_button summary={s} />
              <.meal_menu summary={s} />
            </li>
          </ul>
        </section>

        <section :if={@past != []} id="past-meals" class="min-w-0">
          <h2 class="mb-3 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
            Past meals
            <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@past)}</span>
          </h2>
          <ul class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            <.past_meal
              :for={{s, i} <- Enum.with_index(if(@show_past, do: @past, else: Enum.take(@past, 6)))}
              summary={s}
              photos={Map.get(@past_photos, s.meal.id, [])}
              index={i}
            />
          </ul>
          <button
            :if={length(@past) > 6}
            id="toggle-past"
            type="button"
            phx-click="toggle_past"
            class="btn btn-ghost btn-sm mt-3 rounded-full text-base-content/60"
          >
            <%= if @show_past do %>
              Show fewer <.icon name="hero-chevron-up-micro" class="size-4" />
            <% else %>
              Show all {length(@past)} past meals
              <.icon name="hero-chevron-down-micro" class="size-4" />
            <% end %>
          </button>
        </section>
      </div>

      <section id="dishes" class="mt-12">
        <h2 class="mb-4 flex items-center gap-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          Dishes
          <span class="rounded-full bg-base-content/10 px-2 py-0.5 text-xs">{length(@saved)}</span>
          <.link
            id="create-dish"
            navigate={~p"/dishes/new"}
            class="btn btn-sm btn-glass ml-auto rounded-full normal-case tracking-normal"
          >
            <.icon name="hero-plus-micro" class="size-4" /> New dish
          </.link>
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

      <PhotoViewer.viewer
        :if={@viewer}
        index={@viewer.index}
        photos={Map.get(@past_photos, @viewer.meal_id, [])}
        title={viewed_meal(@past, @viewer).name}
        subtitle={Calendar.strftime(viewed_meal(@past, @viewer).date, "%d %b %Y")}
        link={~p"/meals/#{@viewer.meal_id}/summary"}
      />
    </Layouts.app>
    """
  end
end
