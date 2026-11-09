defmodule CookingSchedulerWeb.CookLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Clock, Cooking, Duration, Kitchen, Meals, Planner, RecipeLink}
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.{Meal, MealDish}

  @tick_ms 15_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(id)

    if connected?(socket) do
      Process.send_after(self(), :tick, @tick_ms)
      Meals.subscribe(meal)
    end

    {:ok, load(socket, meal)}
  end

  # Reads the meal and its progress from the database and derives everything shown.
  defp load(socket), do: load(socket, Meals.get_meal!(socket.assigns.meal.id))

  # How many "Up next" tasks are shown in full before the rest fold away (ADR 0019).
  @soon 4

  defp load(socket, %Meal{} = meal) do
    kitchen = Kitchen.list_appliances()
    entries = Planner.plan(Meals.list_meal_dishes(meal), Meal.serve_minutes(meal), kitchen)

    socket
    |> assign(
      page_title: "Cooking · #{meal.name}",
      meal: meal,
      entries: entries,
      kitchen: kitchen,
      oven_events: Planner.oven_events(entries, kitchen)
    )
    |> derive(Clock.now_minutes())
  end

  defp derive(socket, now) do
    %{meal: meal, entries: entries, oven_events: oven_events, kitchen: kitchen} = socket.assigns
    serve = Meal.serve_minutes(meal)
    lives = Cooking.lives(entries, now)
    behind = Cooking.behind(lives)
    projected = serve + behind
    tasks = Cooking.tasks(lives, now, oven_events, meal.oven_marks)
    open = Enum.reject(tasks, &(&1.state == :done))
    pending = Enum.reject(open, &(&1.kind == :out))
    {soon, later} = Enum.split(pending, @soon)

    socket
    |> assign(
      now: now,
      serve: serve,
      lives: lives,
      projected: projected,
      behind: behind,
      pending: pending,
      soon: soon,
      later: later,
      next_task: Enum.find(open, &(&1.kind != :out or &1.entry.dish.cook_started_at != nil)),
      done: tasks |> Enum.filter(&(&1.state == :done)) |> Enum.reverse(),
      overview: overview(lives, now, serve, projected),
      cooking: Enum.filter(lives, &(&1.phase == :cooking)),
      resting: Enum.filter(lives, &(&1.phase == :resting)),
      ovens: oven_strip(kitchen, lives, oven_events, meal.oven_marks)
    )
    |> alert(open)
  end

  # Tell the browser when something has just become due, so it can chime (ADR 0019). The
  # first derive after mount only remembers what's due, so reloading doesn't ring.
  defp alert(socket, open) do
    due =
      for t <- open, t.state in [:now, :overdue], into: MapSet.new(), do: task_id(t)

    case socket.assigns[:due] do
      nil ->
        assign(socket, :due, due)

      before ->
        fresh =
          for t <- open,
              t.state in [:now, :overdue],
              not MapSet.member?(before, task_id(t)),
              do: verb(t)

        socket
        |> assign(:due, due)
        |> then(&if(fresh == [], do: &1, else: push_event(&1, "tasks_due", %{tasks: fresh})))
    end
  end

  defp task_id(%{entry: e, kind: kind}), do: "#{e.dish.id}-#{kind}"

  # One chip per oven (and other appliance in use): what's in it and at what temperature.
  defp oven_strip(kitchen, lives, oven_events, marks) do
    for app <- kitchen, app.kind in [:oven, :other] do
      inside =
        for l <- lives,
            l.phase == :cooking,
            l.entry.resource && l.entry.resource.id == app.id,
            do: l

      preheating =
        inside == [] and
          Enum.any?(
            oven_events,
            &(&1.kind == :preheat and &1.appliance.id == app.id and &1.id in marks)
          )

      setting =
        case inside do
          [l | _] ->
            temp_label(l.entry.dish)

          [] ->
            Enum.find_value(
              oven_events,
              &(&1.kind == :preheat and &1.appliance.id == app.id and &1.id in marks and
                  temp_text(&1.temp))
            )
        end

      %{
        appliance: app,
        dishes: Enum.map(inside, & &1.entry.dish.name),
        preheating: preheating,
        setting: setting
      }
    end
    |> Enum.filter(&(&1.appliance.kind == :oven or &1.dishes != []))
  end

  defp temp_text({t, :gas_mark}), do: "Gas mark #{Appliance.fmt_temp(t, :gas_mark)}"

  defp temp_text({t, unit}),
    do: "#{Appliance.fmt_temp(t, unit)} #{Appliance.temp_unit_label(unit)}"

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, derive(socket, Clock.now_minutes())}
  end

  # A tap on another device (or the plan changing elsewhere).
  def handle_info({:meal_updated, _id}, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("complete", %{"event" => event_id}, socket) do
    {:ok, _} = Meals.mark_oven_event(socket.assigns.meal, event_id, true)
    {:noreply, load(socket)}
  end

  def handle_event("complete", %{"dish" => id, "kind" => kind}, socket) do
    dish = Meals.get_meal_dish!(id)
    now = Clock.now_minutes()

    {:ok, _} =
      case kind do
        "prep" -> Meals.set_prepped(dish, true)
        "start" -> Meals.start_cooking(dish, now)
        "out" -> Meals.finish_cooking(dish, now)
      end

    {:noreply, load(socket)}
  end

  def handle_event("undo", %{"event" => event_id}, socket) do
    {:ok, _} = Meals.mark_oven_event(socket.assigns.meal, event_id, false)
    {:noreply, load(socket)}
  end

  def handle_event("undo", %{"dish" => id, "kind" => kind}, socket) do
    dish = Meals.get_meal_dish!(id)

    {:ok, _} =
      case kind do
        "prep" -> Meals.set_prepped(dish, false)
        "start" -> Meals.undo_start(dish)
        "out" -> Meals.undo_finish(dish)
      end

    {:noreply, load(socket)}
  end

  def handle_event("extend", %{"dish" => id, "minutes" => minutes}, socket) do
    {:ok, _} = id |> Meals.get_meal_dish!() |> Meals.add_extra(String.to_integer(minutes))
    {:noreply, load(socket)}
  end

  def handle_event("shift_dinner", %{"minutes" => minutes}, socket) do
    {:ok, _} =
      Meals.set_serve_minutes(
        socket.assigns.meal,
        socket.assigns.serve + String.to_integer(minutes)
      )

    {:noreply, load(socket)}
  end

  def handle_event("push_dinner", _params, socket) do
    {:ok, _} = Meals.set_serve_minutes(socket.assigns.meal, socket.assigns.projected)
    {:noreply, load(socket)}
  end

  def handle_event("finish", _params, socket) do
    {:ok, _} = Meals.finish_meal(socket.assigns.meal)
    {:noreply, push_navigate(socket, to: ~p"/meals/#{socket.assigns.meal.id}/summary")}
  end

  def handle_event("reset", _params, socket) do
    :ok = Meals.reset_cooking(socket.assigns.meal)
    {:noreply, load(socket)}
  end

  # ---- overview timeline ----------------------------------------------------

  # One row per dish on a shared time axis: prep, time on the heat, then rest.
  defp overview(lives, now, serve, projected) do
    lives = Enum.reject(lives, &(&1.phase == :unscheduled))

    starts =
      Enum.map(lives, fn l ->
        if prep_today?(l.entry.dish), do: min(l.entry.prep_at, l.cook_at), else: l.cook_at
      end)

    # One serve line per course (ADR 0018).
    serves = lives |> Enum.map(& &1.entry.serve_at) |> Enum.uniq() |> Enum.sort()

    t0 = Enum.min([now | starts])
    t1 = Enum.max([serve, projected, now + 30 | serves])
    span = max(t1 - t0, 1)
    pct = fn m -> Float.round((m - t0) / span * 100, 2) end
    seg = fn from, to -> %{left: pct.(from), width: max(pct.(to) - pct.(from), 0.6)} end

    rows =
      for l <- lives do
        d = l.entry.dish
        prep_to = l.entry.prep_at + d.prep_minutes

        %{
          id: d.id,
          name: d.name,
          phase: l.phase,
          prepped: d.prepped,
          resource: l.entry.resource,
          dish: d,
          prep: prep_today?(d) && seg.(l.entry.prep_at, prep_to),
          cook: seg.(l.cook_at, l.out_at),
          rest: d.rest_minutes > 0 && seg.(l.out_at, l.ready_at),
          times: %{
            prep: prep_today?(d) && {l.entry.prep_at, prep_to},
            cook: {l.cook_at, l.out_at},
            rest: d.rest_minutes > 0 && {l.out_at, l.ready_at}
          }
        }
      end

    groups =
      rows
      |> Enum.group_by(&group_key(&1.resource))
      |> Enum.map(fn {key, rows} ->
        resource = hd(rows).resource

        %{
          id: (key && "#{elem(key, 0)}-#{slug(elem(key, 1))}") || "none",
          resource: resource,
          name: group_name(resource),
          rows: rows
        }
      end)
      |> Enum.sort_by(&group_order/1)

    ticks =
      for m <- (div(t0 + 59, 60) * 60)..t1//60, do: %{at: m, left: pct.(m)}

    %{
      groups: groups,
      rows: rows,
      ticks: ticks,
      now: pct.(now),
      serve: pct.(serve),
      serves: for(at <- serves, do: %{at: at, left: pct.(at), label: course_label(at, serve)}),
      projected: pct.(projected)
    }
  end

  # Prep that happens on the day: just before cooking, or ahead-of-time prep never ticked off.
  defp prep_today?(d), do: d.prep_minutes > 0 and (d.prep_day == :before_cooking or not d.prepped)

  defp course_label(at, serve) when at == serve, do: "serve"
  defp course_label(at, serve), do: MealDish.course(at - serve) |> String.downcase()

  # Hobs group by size ("Medium rings"); everything else by its own name.
  defp group_key(nil), do: nil
  defp group_key(%{kind: :ring, size: size}) when not is_nil(size), do: {:ring, size}
  defp group_key(%{kind: kind, name: name}), do: {kind, name}

  defp group_name(nil), do: "No appliance"

  defp group_name(%{kind: :ring, size: size}) when not is_nil(size),
    do: "#{size |> to_string() |> String.capitalize()} rings"

  defp group_name(%{name: name}), do: name

  defp slug(name) when is_atom(name), do: Atom.to_string(name)
  defp slug(name), do: name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

  defp group_icon(%{kind: :oven}), do: "hero-fire"
  defp group_icon(%{kind: :ring}), do: "hero-stop-circle"
  defp group_icon(%{kind: :other}), do: "hero-bolt"
  defp group_icon(_), do: "hero-question-mark-circle"

  defp group_order(%{resource: nil}), do: {3, "", 0}

  defp group_order(%{resource: r}),
    do: {Enum.find_index(~w(oven ring other)a, &(&1 == r.kind)), group_name(r), 0}

  defp clock_range({from, to}),
    do: "#{Duration.clock(Integer.mod(from, 1440))} – #{Duration.clock(Integer.mod(to, 1440))}"

  defp phase_label(:waiting), do: "Not started"
  defp phase_label(:cooking), do: "Cooking now"
  defp phase_label(:resting), do: "Resting"
  defp phase_label(:ready), do: "Done"
  defp phase_label(_), do: ""

  # Anchors the tooltip to the cook bar, flipping to its edge near the ends of the strip so it
  # stays on screen. Positions are percentages of the row.
  defp tip_style(%{cook: %{left: l, width: w}}) do
    mid = l + w / 2

    cond do
      mid < 25 -> "left: #{max(l, 0)}%"
      mid > 75 -> "right: #{max(100 - l - w, 0)}%"
      true -> "left: #{mid}%; transform: translateX(-50%)"
    end
  end

  defp cook_bar_class(:waiting), do: "bg-primary/35"
  defp cook_bar_class(_), do: "bg-primary"

  defp seg_style(%{left: l, width: w}), do: "left: #{l}%; width: #{w}%"

  # ---- display helpers ------------------------------------------------------

  defp rel(at, now) when at == now, do: "now"
  defp rel(at, now) when at > now, do: "in #{Duration.format(at - now)}"
  defp rel(at, now), do: "#{Duration.format(now - at)} ago"

  defp resource_name(%{resource: nil}), do: nil
  defp resource_name(%{resource: r}), do: r.name

  defp verb(%{kind: :preheat, event: ev}),
    do: "Switch on #{ev.appliance.name} to #{temp_text(ev.temp)}"

  defp verb(%{kind: :adjust, event: ev}), do: "Turn #{ev.appliance.name} to #{temp_text(ev.temp)}"
  defp verb(%{kind: :prep, entry: e}), do: "Prep #{e.dish.name}"

  defp verb(%{kind: :start, entry: %{dish: %{method: :oven} = d} = e}),
    do: "Put #{d.name} in #{resource_name(e) || "the oven"}"

  defp verb(%{kind: :start, entry: %{dish: %{method: :ring} = d} = e}),
    do: "Start #{d.name} on #{resource_name(e) || "the hob"}"

  defp verb(%{kind: :start, entry: %{dish: d} = e}),
    do: "Start #{d.name}" <> if(resource_name(e), do: " in #{resource_name(e)}", else: "")

  defp verb(%{kind: :out, entry: %{dish: %{method: :oven} = d} = e}),
    do: "Take #{d.name} out" <> if(resource_name(e), do: " of #{resource_name(e)}", else: "")

  defp verb(%{kind: :out, entry: %{dish: %{method: :ring} = d}}),
    do: "Take #{d.name} off the heat"

  defp verb(%{kind: :out, entry: %{dish: d}}), do: "#{d.name} is done"

  defp button_label(:preheat), do: "It's on"
  defp button_label(:adjust), do: "Done"
  defp button_label(:prep), do: "Prepped"
  defp button_label(:start), do: "Started"
  defp button_label(:out), do: "Done"

  defp out_label(%{method: :oven}), do: "Take out"
  defp out_label(%{method: :ring}), do: "Off the heat"
  defp out_label(_dish), do: "Done"

  defp temp_label(%{temp: nil}), do: nil

  defp temp_label(%{temp: t, temp_unit: :gas_mark}),
    do: "Gas mark #{Appliance.fmt_temp(t, :gas_mark)}"

  defp temp_label(%{temp: t, temp_unit: u}),
    do: "#{Appliance.fmt_temp(t, u)} #{Appliance.temp_unit_label(u)}"

  defp state_class(:overdue), do: "border-error/60 bg-error/5"
  defp state_class(:now), do: "border-primary bg-primary/10 shadow-lg shadow-primary/10"
  defp state_class(_), do: "border-base-300 bg-base-100/90"

  defp rel_class(:overdue), do: "text-error font-semibold"
  defp rel_class(:now), do: "text-primary font-semibold"
  defp rel_class(_), do: "text-base-content/50"

  # ---- components -----------------------------------------------------------

  attr :task, :any, required: true
  attr :now, :integer, required: true

  defp task_card(assigns) do
    assigns = assign(assigns, dish: assigns.task.entry.dish)

    ~H"""
    <li
      id={"task-#{@dish.id}-#{@task.kind}"}
      class={[
        "pop-in flex items-center gap-3 rounded-xl border px-3 py-2.5 transition",
        state_class(@task.state)
      ]}
    >
      <div class="w-16 shrink-0 text-center">
        <div class="text-xl font-extrabold leading-tight tabular-nums">
          {Duration.clock(@task.at)}
        </div>
        <div class={["text-[11px] leading-tight", rel_class(@task.state)]}>
          {if @task.state == :overdue,
            do: "#{Duration.format(@now - @task.at)} late",
            else: rel(@task.at, @now)}
        </div>
      </div>

      <div class="min-w-0 flex-1">
        <div class="font-semibold leading-snug">{verb(@task)}</div>
        <div class="mt-1 flex flex-wrap items-center gap-1">
          <span :if={@task.event} class="badge badge-ghost badge-sm">
            <.icon name="hero-fire-micro" class="size-3" /> for {@dish.name}
          </span>
          <span
            :if={@task.kind == :start and temp_label(@dish)}
            class="badge badge-primary badge-soft badge-sm"
          >
            <.icon name="hero-fire-micro" class="size-3" /> {temp_label(@dish)}
          </span>
          <span :if={@task.kind == :out and @dish.rest_minutes > 0} class="badge badge-ghost badge-sm">
            then rest {Duration.format(@dish.rest_minutes)}
          </span>
          <span :if={@dish.extra_minutes > 0} class="badge badge-warning badge-soft badge-sm">
            +{@dish.extra_minutes}m added
          </span>
          <.link
            :if={is_nil(@task.event)}
            id={"details-#{@dish.id}-#{@task.kind}"}
            navigate={~p"/meals/#{@dish.meal_id}/dishes/#{@dish.id}?from=cook"}
            class="badge badge-ghost badge-sm hover:badge-primary"
          >
            <.icon name="hero-list-bullet-micro" class="size-3" /> Details
          </.link>
          <a
            :if={is_nil(@task.event) and @dish.link not in [nil, ""]}
            href={@dish.link}
            target="_blank"
            rel="noopener"
            title={RecipeLink.host(@dish.link)}
            class="badge badge-ghost badge-sm hover:badge-primary"
          >
            <.icon name="hero-arrow-top-right-on-square-micro" class="size-3" /> Recipe
          </a>
        </div>
        <p
          :if={@task.kind not in [:prep, :preheat, :adjust] and @dish.notes not in [nil, ""]}
          class="mt-1 line-clamp-1 text-xs text-base-content/60"
        >
          {@dish.notes}
        </p>
      </div>

      <button
        class={[
          "btn btn-sm shrink-0 rounded-full px-4",
          (@task.state in [:overdue, :now] && "btn-primary") || "btn-soft"
        ]}
        phx-click="complete"
        phx-value-dish={@dish.id}
        phx-value-kind={@task.kind}
        phx-value-event={@task.event && @task.event.id}
      >
        <.icon name="hero-check" class="size-4" /> {button_label(@task.kind)}
      </button>
    </li>
    """
  end

  attr :live, :any, required: true
  attr :now, :integer, required: true

  defp progress_card(assigns) do
    assigns = assign(assigns, dish: assigns.live.entry.dish)

    ~H"""
    <li id={"cooking-#{@dish.id}"} class="rounded-2xl border border-base-300 bg-base-100/90 p-4">
      <div class="flex items-center justify-between gap-2">
        <span class="font-semibold">{@dish.name}</span>
        <span :if={resource_name(@live.entry)} class="badge badge-secondary badge-soft badge-sm">
          {resource_name(@live.entry)}
        </span>
      </div>
      <progress class="progress progress-primary mt-3 w-full" value={@live.progress} max="100"></progress>
      <div class="mt-2 flex items-baseline justify-between text-sm">
        <span>Out at <b class="tabular-nums">{Duration.clock(@live.out_at)}</b></span>
        <span class={[@live.out_at < @now && "font-semibold text-error"]}>
          {if @live.out_at < @now,
            do: "#{Duration.format(@now - @live.out_at)} over",
            else: rel(@live.out_at, @now)}
        </span>
      </div>
      <div class="mt-3 flex flex-wrap items-center gap-1.5">
        <span class="mr-1 text-xs text-base-content/60">Taking longer?</span>
        <button
          :for={m <- [5, 10, 15, 30]}
          class="btn btn-xs rounded-full"
          phx-click="extend"
          phx-value-dish={@dish.id}
          phx-value-minutes={m}
        >
          +{m}m
        </button>
      </div>
      <button
        id={"out-#{@dish.id}"}
        class={[
          "btn btn-sm mt-3 w-full rounded-full",
          (@live.out_at <= @now && "btn-primary") || "btn-soft"
        ]}
        phx-click="complete"
        phx-value-dish={@dish.id}
        phx-value-kind="out"
      >
        <.icon name="hero-check" class="size-4" /> {out_label(@dish)}
      </button>
    </li>
    """
  end

  attr :overview, :map, required: true

  defp overview_panel(assigns) do
    ~H"""
    <section
      id="overview"
      class="rounded-2xl border border-base-300 bg-base-100/90 p-4"
      aria-label="Whole meal timeline"
    >
      <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
        <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
          The whole meal
        </h2>
        <div class="flex flex-wrap items-center gap-3 text-xs text-base-content/60">
          <span class="inline-flex items-center gap-1">
            <span class="size-2.5 rounded-sm bg-base-content/25"></span> Prep
          </span>
          <span class="inline-flex items-center gap-1">
            <span class="size-2.5 rounded-sm bg-primary"></span> Cooking
          </span>
          <span class="inline-flex items-center gap-1">
            <span class="size-2.5 rounded-sm bg-secondary/50"></span> Resting
          </span>
        </div>
      </div>

      <div class="flex">
        <div class="w-24 shrink-0 sm:w-40">
          <div class="h-5"></div>
          <%= for g <- @overview.groups do %>
            <div
              id={"overview-group-label-#{g.id}"}
              class="mt-2 flex h-8 items-center gap-1.5 rounded-l-lg bg-base-200 pl-2 pr-3 text-xs font-bold uppercase tracking-wider text-base-content/80"
            >
              <.icon name={group_icon(g.resource)} class="size-4 shrink-0 text-primary" />
              <span class="truncate">{g.name}</span>
              <span class="ml-auto font-medium normal-case tracking-normal text-base-content/50">
                {length(g.rows)}
              </span>
            </div>
            <div
              :for={r <- g.rows}
              id={"overview-label-#{r.id}"}
              class={[
                "ml-2.5 flex h-7 items-center truncate border-l-2 border-primary/30 pl-3 pr-3 text-sm",
                (r.phase == :ready && "text-base-content/40") || "font-medium"
              ]}
              title={r.name}
            >
              <span class="truncate">{r.name}</span>
            </div>
          <% end %>
        </div>

        <div class="relative min-w-0 flex-1">
          <div class="relative h-5 text-[11px] tabular-nums text-base-content/50">
            <span
              :for={t <- @overview.ticks}
              class="absolute -translate-x-1/2"
              style={"left: #{t.left}%"}
            >
              {Duration.clock(t.at)}
            </span>
          </div>

          <span
            :for={t <- @overview.ticks}
            class="pointer-events-none absolute bottom-0 top-5 w-px bg-base-300/60"
            style={"left: #{t.left}%"}
          ></span>

          <%= for g <- @overview.groups do %>
            <div class="mt-2 h-8 rounded-r-lg bg-base-200"></div>
            <div
              :for={r <- g.rows}
              id={"overview-row-#{r.id}"}
              tabindex="0"
              class="group relative h-7 border-t border-base-200 outline-none hover:z-20 focus:z-20"
            >
              <span
                :if={r.prep}
                class={[
                  "absolute top-2 h-3 rounded-sm",
                  (r.prepped && "bg-success/60") || "bg-base-content/25"
                ]}
                style={seg_style(r.prep)}
              ></span>
              <span
                class={[
                  "absolute top-1 h-5 rounded-md transition group-hover:brightness-95 group-focus:brightness-95",
                  cook_bar_class(r.phase)
                ]}
                style={seg_style(r.cook)}
              ></span>
              <span
                :if={r.rest}
                class="absolute top-2 h-3 rounded-sm bg-secondary/50"
                style={seg_style(r.rest)}
              ></span>
              <div
                id={"overview-tip-#{r.id}"}
                role="tooltip"
                class={[
                  "pointer-events-none invisible absolute bottom-full z-30 mb-1 w-max max-w-64 rounded-xl border border-base-300 bg-base-100 p-3 text-left opacity-0 shadow-xl shadow-base-content/10 transition-opacity duration-150 group-hover:visible group-hover:opacity-100 group-focus:visible group-focus:opacity-100"
                ]}
                style={tip_style(r)}
              >
                <div class="text-sm font-semibold">{r.name}</div>
                <div class="text-xs text-base-content/50">
                  {g.name} · {phase_label(r.phase)}
                </div>
                <dl class="mt-2 space-y-1 text-xs tabular-nums">
                  <div :if={r.times.prep} class="flex justify-between gap-4">
                    <dt class="text-base-content/60">Prep</dt>
                    <dd class="font-medium">{clock_range(r.times.prep)}</dd>
                  </div>
                  <div class="flex justify-between gap-4">
                    <dt class="text-base-content/60">Cooking</dt>
                    <dd class="font-medium">{clock_range(r.times.cook)}</dd>
                  </div>
                  <div :if={r.times.rest} class="flex justify-between gap-4">
                    <dt class="text-base-content/60">Resting</dt>
                    <dd class="font-medium">{clock_range(r.times.rest)}</dd>
                  </div>
                </dl>
                <div :if={temp_label(r.dish)} class="mt-2 border-t border-base-300 pt-1.5 text-xs">
                  {temp_label(r.dish)}
                </div>
              </div>
            </div>
          <% end %>

          <span
            :for={c <- @overview.serves}
            id={"overview-serve-#{c.at}"}
            class="pointer-events-none absolute bottom-0 top-0 w-0.5 bg-secondary"
            style={"left: #{c.left}%"}
          >
            <span class="absolute -top-0.5 left-1/2 -translate-x-1/2 rounded bg-secondary px-1 text-[10px] font-bold leading-4 text-secondary-content">
              {c.label}
            </span>
          </span>
          <span
            id="overview-now"
            class="pointer-events-none absolute bottom-0 top-0 w-0.5 bg-error"
            style={"left: #{@overview.now}%"}
          >
            <span class="absolute -top-0.5 left-1/2 -translate-x-1/2 rounded bg-error px-1 text-[10px] font-bold leading-4 text-error-content">
              now
            </span>
          </span>
        </div>
      </div>
    </section>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="pop-in flex flex-wrap items-center justify-between gap-x-6 gap-y-2 rounded-2xl bg-gradient-to-br from-primary via-primary to-secondary px-4 py-3 text-primary-content shadow-lg shadow-primary/20">
        <div class="flex items-baseline gap-2">
          <span class="text-xs font-medium uppercase tracking-wider text-primary-content/70">Now</span>
          <span id="clock" class="text-3xl font-extrabold tabular-nums leading-none">
            {Duration.clock(@now)}<span
              id="clock-seconds"
              phx-hook=".ClockSeconds"
              phx-update="ignore"
              class="text-xl font-bold text-primary-content/70"
            >:00</span>
          </span>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".ClockSeconds">
            export default {
              mounted() {
                const tick = () => {
                  this.el.textContent = ":" + String(new Date().getSeconds()).padStart(2, "0")
                }
                tick()
                this.timer = setInterval(tick, 1000)
              },
              destroyed() {
                clearInterval(this.timer)
              }
            }
          </script>
        </div>

        <div :if={@next_task} id="next-action" class="flex items-baseline gap-2">
          <span class="text-xs font-medium uppercase tracking-wider text-primary-content/70">
            Next
          </span>
          <span id="next-action-time" class="text-2xl font-extrabold tabular-nums leading-none">
            {if @next_task.at <= @now, do: "now", else: Duration.format(@next_task.at - @now)}
          </span>
          <span class="max-w-48 truncate text-sm text-primary-content/80">{verb(@next_task)}</span>
        </div>

        <div class="flex items-center gap-2">
          <span class="text-xs font-medium uppercase tracking-wider text-primary-content/70">
            Dinner
          </span>
          <button
            class="btn btn-circle btn-xs border-0 bg-white/20 text-primary-content hover:bg-white/30"
            phx-click="shift_dinner"
            phx-value-minutes="-5"
            aria-label="Dinner 5 minutes earlier"
          >
            <.icon name="hero-minus-micro" class="size-3.5" />
          </button>
          <span id="dinner-time" class="text-2xl font-extrabold tabular-nums">{Duration.clock(@serve)}</span>
          <button
            class="btn btn-circle btn-xs border-0 bg-white/20 text-primary-content hover:bg-white/30"
            phx-click="shift_dinner"
            phx-value-minutes="5"
            aria-label="Dinner 5 minutes later"
          >
            <.icon name="hero-plus-micro" class="size-3.5" />
          </button>
          <span class="text-sm text-primary-content/80">
            {if @serve > @now, do: "in #{Duration.format(@serve - @now)}", else: "now!"}
          </span>
        </div>

        <div
          id="cook-tools"
          phx-hook=".CookTools"
          phx-update="ignore"
          class="flex items-center gap-1"
        >
          <button
            type="button"
            data-sound
            aria-pressed="false"
            class="btn btn-circle btn-xs border-0 bg-white/20 text-primary-content hover:bg-white/30 aria-pressed:bg-white aria-pressed:text-primary"
            title="Chime and notify when something is due"
            aria-label="Sound alerts"
          >
            <.icon name="hero-bell-micro" class="size-3.5" />
          </button>
          <button
            type="button"
            data-big
            aria-pressed="false"
            class="btn btn-circle btn-xs border-0 bg-white/20 text-primary-content hover:bg-white/30 aria-pressed:bg-white aria-pressed:text-primary"
            title="Bigger type and buttons for the kitchen"
            aria-label="Kitchen mode"
          >
            <.icon name="hero-magnifying-glass-plus-micro" class="size-3.5" />
          </button>
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".CookTools">
          // Alerts, keep-awake and kitchen mode for the cook screen (ADR 0019). All state is
          // per device, kept in localStorage; the server only says when something is due.
          export default {
            mounted() {
              this.sound = this.el.querySelector("[data-sound]")
              this.big = this.el.querySelector("[data-big]")
              this.setSound(this.read("cook:sound") === "on", false)
              this.setBig(this.read("cook:big") === "on")

              this.sound.addEventListener("click", () => this.setSound(!this.on, true))
              this.big.addEventListener("click", () => this.setBig(!this.isBig))

              this.handleEvent("tasks_due", ({tasks}) => this.alert(tasks))

              this.wake()
              this.onVisible = () => document.visibilityState === "visible" && this.wake()
              document.addEventListener("visibilitychange", this.onVisible)
            },

            destroyed() {
              document.removeEventListener("visibilitychange", this.onVisible)
              if(this.lock) this.lock.release().catch(() => {})
              document.documentElement.classList.remove("kitchen-big")
            },

            read(key) { try { return localStorage.getItem(key) } catch(_e) { return null } },
            write(key, value) { try { localStorage.setItem(key, value) } catch(_e) {} },

            setSound(on, byUser) {
              this.on = on
              this.sound.setAttribute("aria-pressed", String(on))
              this.write("cook:sound", on ? "on" : "off")
              if(on && byUser){
                this.chime()
                if("Notification" in window && Notification.permission === "default") Notification.requestPermission()
              }
            },

            setBig(on) {
              this.isBig = on
              this.big.setAttribute("aria-pressed", String(on))
              this.write("cook:big", on ? "on" : "off")
              document.documentElement.classList.toggle("kitchen-big", on)
            },

            async wake() {
              if(!("wakeLock" in navigator)) return
              try { this.lock = await navigator.wakeLock.request("screen") } catch(_e) {}
            },

            alert(tasks) {
              if(!this.on) return
              this.chime()
              if("Notification" in window && Notification.permission === "granted" && document.visibilityState !== "visible"){
                new Notification(tasks[0], {body: tasks.slice(1).join("\n") || "Time to do it", tag: "cook"})
              }
            },

            // Two short notes, no audio file needed.
            chime() {
              try {
                const ctx = this.ctx || (this.ctx = new (window.AudioContext || window.webkitAudioContext)())
                const play = (freq, at) => {
                  const osc = ctx.createOscillator()
                  const gain = ctx.createGain()
                  osc.type = "sine"
                  osc.frequency.value = freq
                  gain.gain.setValueAtTime(0.0001, at)
                  gain.gain.exponentialRampToValueAtTime(0.3, at + 0.02)
                  gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.35)
                  osc.connect(gain).connect(ctx.destination)
                  osc.start(at)
                  osc.stop(at + 0.4)
                }
                play(880, ctx.currentTime)
                play(1175, ctx.currentTime + 0.25)
              } catch(_e) {}
            }
          }
        </script>

        <div id="status" class="flex flex-wrap items-center gap-2">
          <div
            :if={@behind <= 0}
            class="inline-flex items-center gap-1.5 rounded-full bg-white/20 px-3 py-1 text-sm font-semibold"
          >
            <.icon name="hero-check-circle-micro" class="size-4" /> On track
          </div>
          <div
            :if={@behind > 0}
            class="inline-flex items-center gap-1.5 rounded-full bg-warning px-3 py-1 text-sm font-semibold text-warning-content"
          >
            <.icon name="hero-clock-micro" class="size-4" /> Running {Duration.format(@behind)} behind
          </div>
          <button
            :if={@behind > 0}
            id="push-dinner"
            class="btn btn-sm rounded-full border-0 bg-white text-primary shadow hover:bg-white/90"
            phx-click="push_dinner"
          >
            Move dinner to {Duration.clock(@projected)}
          </button>
        </div>
      </div>

      <div :if={@ovens != []} id="oven-strip" class="mt-3 flex flex-wrap gap-2">
        <div
          :for={o <- @ovens}
          id={"oven-now-#{o.appliance.id}"}
          class={[
            "flex items-center gap-2 rounded-full border px-3 py-1 text-sm",
            (o.dishes != [] && "border-primary/40 bg-primary/10") || "border-base-300 bg-base-100/80"
          ]}
        >
          <.icon
            name={group_icon(o.appliance)}
            class={["size-4", (o.dishes != [] or o.preheating) && "text-primary"]}
          />
          <span class="font-semibold">{o.appliance.name}</span>
          <span :if={o.setting} class="text-xs text-base-content/70">{o.setting}</span>
          <span class="text-xs text-base-content/60">
            <%= cond do %>
              <% o.dishes != [] -> %>
                {Enum.join(o.dishes, ", ")}
              <% o.preheating -> %>
                heating up
              <% true -> %>
                free
            <% end %>
          </span>
        </div>
      </div>

      <div
        :if={@lives == [] or Enum.all?(@lives, &(&1.phase == :unscheduled))}
        class="mt-8 rounded-3xl border border-dashed border-base-300 p-8 text-center text-base-content/60"
      >
        Nothing to cook yet.
        <.link navigate={~p"/meals/#{@meal.id}/plan"} class="link link-primary">Add your dishes</.link>
        first.
      </div>

      <div
        :if={Enum.any?(@lives, &(&1.phase != :unscheduled))}
        class="mt-6 grid items-start gap-6 xl:grid-cols-[26rem_minmax(0,1fr)]"
      >
        <div class="space-y-6 xl:sticky xl:top-4 xl:max-h-[calc(100vh-2rem)] xl:overflow-y-auto xl:pr-1">
          <section :if={@cooking != []}>
            <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/50">
              In progress
            </h2>
            <ul id="in-progress" class="space-y-3">
              <.progress_card :for={l <- @cooking} live={l} now={@now} />
            </ul>
          </section>

          <section>
            <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/50">
              Up next
            </h2>
            <div
              :if={@pending == []}
              id="all-done"
              class="pop-in rounded-3xl bg-gradient-to-br from-secondary/15 to-accent/20 p-10 text-center"
            >
              <div class="text-5xl">🎄</div>
              <div class="mt-3 text-2xl font-bold">Everything's done</div>
              <p class="mt-1 text-base-content/60">Time to serve. Merry Christmas!</p>
            </div>
            <ul :if={@pending != []} id="tasks" class="space-y-3">
              <.task_card :for={t <- @soon} task={t} now={@now} />
            </ul>
            <div :if={@later != []} class="mt-3">
              <button
                id="later-toggle"
                type="button"
                class="flex w-full items-center justify-between rounded-xl px-1 py-1 text-sm font-semibold text-base-content/60 hover:text-primary"
                phx-click={JS.toggle(to: "#later")}
              >
                <span>Later ({length(@later)}) · next at {Duration.clock(hd(@later).at)}</span>
                <.icon name="hero-chevron-down-micro" class="size-4" />
              </button>
              <ul id="later" style="display: none" class="mt-2 space-y-3">
                <.task_card :for={t <- @later} task={t} now={@now} />
              </ul>
            </div>
          </section>

          <section :if={@resting != []}>
            <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/50">
              Resting
            </h2>
            <ul id="resting" class="space-y-2">
              <li
                :for={l <- @resting}
                class="flex items-center justify-between rounded-2xl border border-base-300 bg-base-100/90 px-4 py-3"
              >
                <span class="font-medium">{l.entry.dish.name}</span>
                <span class="text-sm text-base-content/60">ready {Duration.clock(l.ready_at)} · {rel(
                  l.ready_at,
                  @now
                )}</span>
              </li>
            </ul>
          </section>

          <section :if={@done != []}>
            <button
              class="flex w-full items-center justify-between text-sm font-semibold uppercase tracking-wider text-base-content/50"
              phx-click={JS.toggle(to: "#done-list")}
            >
              <span>Done ({length(@done)})</span>
              <.icon name="hero-chevron-down-micro" class="size-4" />
            </button>
            <ul id="done-list" style="display: none" class="mt-3 space-y-1.5">
              <li
                :for={t <- @done}
                id={"done-#{t.entry.dish.id}-#{t.kind}"}
                class="flex items-center gap-2 text-sm text-base-content/60"
              >
                <.icon name="hero-check-circle-micro" class="size-4 text-success" />
                <span class="flex-1 truncate">{verb(t)}</span>
                <button
                  class="link link-hover"
                  phx-click="undo"
                  phx-value-dish={t.entry.dish.id}
                  phx-value-kind={t.kind}
                  phx-value-event={t.event && t.event.id}
                >undo</button>
              </li>
            </ul>
          </section>

          <div class="flex flex-wrap gap-2">
            <.link
              id="run-sheet"
              navigate={~p"/meals/#{@meal.id}/sheet"}
              class="btn btn-xs rounded-full"
            >
              <.icon name="hero-printer-micro" class="size-3.5" /> Run sheet
            </.link>
            <.confirm_button
              id="finish-cooking"
              title="Finish cooking now?"
              message="Dishes that aren't done yet are left out of the result."
              confirm_label="Finish"
              on_confirm={JS.push("finish")}
              class="btn btn-xs rounded-full"
            >
              <.icon name="hero-flag-micro" class="size-3.5" /> Finish cooking
            </.confirm_button>
            <button class="btn btn-ghost btn-xs" phx-click="reset">Reset progress</button>
          </div>
        </div>

        <.overview_panel :if={@overview.rows != []} overview={@overview} />
      </div>
    </Layouts.app>
    """
  end
end
