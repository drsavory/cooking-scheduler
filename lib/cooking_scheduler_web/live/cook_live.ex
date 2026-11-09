defmodule CookingSchedulerWeb.CookLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Clock, Cooking, Duration, Kitchen, Meals, Planner, RecipeLink}
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.Meal

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

  defp load(socket, %Meal{} = meal) do
    entries =
      Planner.plan(
        Meals.list_meal_dishes(meal),
        Meal.serve_minutes(meal),
        Kitchen.list_appliances()
      )

    socket
    |> assign(page_title: "Cooking · #{meal.name}", meal: meal, entries: entries)
    |> derive(Clock.now_minutes())
  end

  defp derive(socket, now) do
    serve = Meal.serve_minutes(socket.assigns.meal)
    lives = Cooking.lives(socket.assigns.entries, now)
    projected = Cooking.projected_serve(lives, serve)
    tasks = Cooking.tasks(lives, now)
    open = Enum.reject(tasks, &(&1.state == :done))

    assign(socket,
      now: now,
      serve: serve,
      lives: lives,
      projected: projected,
      behind: projected - serve,
      pending: Enum.reject(open, &(&1.kind == :out)),
      next_task: Enum.find(open, &(&1.kind != :out or &1.entry.dish.cook_started_at != nil)),
      done: tasks |> Enum.filter(&(&1.state == :done)) |> Enum.reverse(),
      overview: overview(lives, now, serve, projected),
      cooking: Enum.filter(lives, &(&1.phase == :cooking)),
      resting: Enum.filter(lives, &(&1.phase == :resting))
    )
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, derive(socket, Clock.now_minutes())}
  end

  # A tap on another device (or the plan changing elsewhere).
  def handle_info({:meal_updated, _id}, socket), do: {:noreply, load(socket)}

  @impl true
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
        if l.entry.dish.prep_minutes > 0, do: min(l.entry.prep_at, l.cook_at), else: l.cook_at
      end)

    t0 = Enum.min([now | starts])
    t1 = Enum.max([serve, projected, now + 30])
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
          prep: d.prep_minutes > 0 && seg.(l.entry.prep_at, prep_to),
          cook: seg.(l.cook_at, l.out_at),
          rest: d.rest_minutes > 0 && seg.(l.out_at, l.ready_at),
          times: %{
            prep: d.prep_minutes > 0 && {l.entry.prep_at, prep_to},
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
      projected: pct.(projected)
    }
  end

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
            id={"details-#{@dish.id}-#{@task.kind}"}
            navigate={~p"/meals/#{@dish.meal_id}/dishes/#{@dish.id}?from=cook"}
            class="badge badge-ghost badge-sm hover:badge-primary"
          >
            <.icon name="hero-list-bullet-micro" class="size-3" /> Details
          </.link>
          <a
            :if={@dish.link not in [nil, ""]}
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
          :if={@task.kind != :prep and @dish.notes not in [nil, ""]}
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
            id="overview-serve"
            class="pointer-events-none absolute bottom-0 top-0 w-0.5 bg-secondary"
            style={"left: #{@overview.serve}%"}
          ></span>
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
              <.task_card :for={t <- @pending} task={t} now={@now} />
            </ul>
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
                >undo</button>
              </li>
            </ul>
          </section>

          <div class="flex gap-2">
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
