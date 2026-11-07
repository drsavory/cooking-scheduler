defmodule CookingSchedulerWeb.CookLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Clock, Cooking, Duration, Kitchen, Meals, Planner}
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.Meal

  @tick_ms 15_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, @tick_ms)
    {:ok, socket |> load(Meals.get_meal!(id))}
  end

  # Reads the meal and its progress from the database and derives everything shown.
  defp load(socket), do: load(socket, Meals.get_meal!(socket.assigns.meal.id))

  defp load(socket, %Meal{} = meal) do
    entries =
      Planner.plan(Meals.list_dishes(meal), Meal.serve_minutes(meal), Kitchen.list_appliances())

    socket
    |> assign(page_title: "Cooking · #{meal.name}", meal: meal, entries: entries)
    |> derive(Clock.now_minutes())
  end

  defp derive(socket, now) do
    serve = Meal.serve_minutes(socket.assigns.meal)
    lives = Cooking.lives(socket.assigns.entries, now)
    projected = Cooking.projected_serve(lives, serve)
    tasks = Cooking.tasks(lives, now)

    assign(socket,
      now: now,
      serve: serve,
      lives: lives,
      projected: projected,
      behind: projected - serve,
      pending: Enum.reject(tasks, &(&1.state == :done)),
      done: tasks |> Enum.filter(&(&1.state == :done)) |> Enum.reverse(),
      cooking: Enum.filter(lives, &(&1.phase == :cooking)),
      resting: Enum.filter(lives, &(&1.phase == :resting))
    )
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, derive(socket, Clock.now_minutes())}
  end

  @impl true
  def handle_event("complete", %{"dish" => id, "kind" => kind}, socket) do
    dish = Meals.get_dish!(id)
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
    dish = Meals.get_dish!(id)

    {:ok, _} =
      case kind do
        "prep" -> Meals.set_prepped(dish, false)
        "start" -> Meals.undo_start(dish)
        "out" -> Meals.undo_finish(dish)
      end

    {:noreply, load(socket)}
  end

  def handle_event("extend", %{"dish" => id, "minutes" => minutes}, socket) do
    {:ok, _} = id |> Meals.get_dish!() |> Meals.add_extra(String.to_integer(minutes))
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
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("reset", _params, socket) do
    :ok = Meals.reset_cooking(socket.assigns.meal)
    {:noreply, load(socket)}
  end

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
        "pop-in flex items-center gap-4 rounded-2xl border p-4 transition",
        state_class(@task.state)
      ]}
    >
      <div class="w-20 shrink-0 text-center">
        <div class="text-2xl font-extrabold tabular-nums">{Duration.clock(@task.at)}</div>
        <div class={["text-xs", rel_class(@task.state)]}>
          {if @task.state == :overdue,
            do: "#{Duration.format(@now - @task.at)} late",
            else: rel(@task.at, @now)}
        </div>
      </div>

      <div class="min-w-0 flex-1">
        <div class="text-lg font-semibold leading-snug">{verb(@task)}</div>
        <div class="mt-1 flex flex-wrap items-center gap-1.5">
          <span
            :if={@task.kind == :start and temp_label(@dish)}
            class="badge badge-primary badge-soft"
          >
            <.icon name="hero-fire-micro" class="size-3.5" /> {temp_label(@dish)}
          </span>
          <span :if={@task.kind == :out and @dish.rest_minutes > 0} class="badge badge-ghost">
            then rest {Duration.format(@dish.rest_minutes)}
          </span>
          <span :if={@dish.extra_minutes > 0} class="badge badge-warning badge-soft">
            +{@dish.extra_minutes}m added
          </span>
          <a
            :if={@dish.link not in [nil, ""]}
            href={@dish.link}
            target="_blank"
            rel="noopener"
            class="badge badge-ghost hover:badge-primary"
          >
            <.icon name="hero-arrow-top-right-on-square-micro" class="size-3.5" /> Recipe
          </a>
        </div>
        <p
          :if={@task.kind != :prep and @dish.notes not in [nil, ""]}
          class="mt-1.5 line-clamp-2 whitespace-pre-line text-sm text-base-content/60"
        >
          {@dish.notes}
        </p>
      </div>

      <button
        class={[
          "btn btn-lg shrink-0 rounded-full px-6",
          (@task.state in [:overdue, :now] && "btn-primary") || "btn-soft"
        ]}
        phx-click="complete"
        phx-value-dish={@dish.id}
        phx-value-kind={@task.kind}
      >
        <.icon name="hero-check" class="size-5" /> {button_label(@task.kind)}
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
    </li>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="pop-in relative overflow-hidden rounded-[2rem] bg-gradient-to-br from-primary via-primary to-secondary p-6 text-primary-content shadow-xl shadow-primary/20 sm:p-8">
        <div class="float-slow pointer-events-none absolute -right-8 -top-12 size-48 rounded-full border-[24px] border-white/10">
        </div>
        <div class="relative grid items-center gap-6 md:grid-cols-[auto_1fr_auto]">
          <div>
            <div class="text-sm font-medium uppercase tracking-wider text-primary-content/70">
              Now
            </div>
            <div id="clock" class="text-6xl font-extrabold tabular-nums leading-none sm:text-7xl">
              {Duration.clock(@now)}
            </div>
          </div>

          <div class="md:justify-self-center">
            <div class="text-sm font-medium uppercase tracking-wider text-primary-content/70">
              Dinner
            </div>
            <div class="mt-1 flex items-center gap-3">
              <button
                class="btn btn-circle btn-sm border-0 bg-white/20 text-primary-content hover:bg-white/30"
                phx-click="shift_dinner"
                phx-value-minutes="-5"
                aria-label="Dinner 5 minutes earlier"
              >
                <.icon name="hero-minus" class="size-4" />
              </button>
              <span id="dinner-time" class="text-4xl font-extrabold tabular-nums">{Duration.clock(
                @serve
              )}</span>
              <button
                class="btn btn-circle btn-sm border-0 bg-white/20 text-primary-content hover:bg-white/30"
                phx-click="shift_dinner"
                phx-value-minutes="5"
                aria-label="Dinner 5 minutes later"
              >
                <.icon name="hero-plus" class="size-4" />
              </button>
            </div>
            <div class="mt-1 text-sm text-primary-content/80">
              {if @serve > @now, do: "in #{Duration.format(@serve - @now)}", else: "now!"}
            </div>
          </div>

          <div id="status" class="md:justify-self-end">
            <div
              :if={@behind <= 0}
              class="inline-flex items-center gap-2 rounded-full bg-white/20 px-4 py-2 font-semibold"
            >
              <.icon name="hero-check-circle" class="size-5" /> On track
            </div>
            <div :if={@behind > 0} class="space-y-2">
              <div class="inline-flex items-center gap-2 rounded-full bg-warning px-4 py-2 font-semibold text-warning-content">
                <.icon name="hero-clock" class="size-5" /> Running {Duration.format(@behind)} behind
              </div>
              <div>
                <button
                  id="push-dinner"
                  class="btn rounded-full border-0 bg-white text-primary shadow-lg hover:bg-white/90"
                  phx-click="push_dinner"
                >
                  Move dinner to {Duration.clock(@projected)}
                </button>
              </div>
            </div>
          </div>
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
        class="mt-8 grid items-start gap-8 lg:grid-cols-[1fr_24rem]"
      >
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

        <aside class="space-y-6 lg:sticky lg:top-4">
          <section :if={@cooking != []}>
            <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/50">
              In progress
            </h2>
            <ul id="in-progress" class="space-y-3">
              <.progress_card :for={l <- @cooking} live={l} now={@now} />
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
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
