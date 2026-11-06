defmodule CookingSchedulerWeb.HomeLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.Kitchen
  alias CookingScheduler.Kitchen.Appliance

  @impl true
  def mount(_params, _session, socket) do
    case Kitchen.list_appliances() do
      # Nothing set up yet: this is a first visit, so start with setup.
      [] ->
        {:ok, push_navigate(socket, to: ~p"/setup")}

      appliances ->
        {:ok,
         socket
         |> assign(:page_title, "Home")
         |> assign(:ovens, Enum.filter(appliances, &(&1.kind == :oven)))
         |> assign(:others, Enum.filter(appliances, &(&1.kind == :other)))
         |> assign(:ring_counts, Kitchen.ring_counts())}
    end
  end

  defp ring_total(counts), do: counts |> Map.values() |> Enum.sum()

  defp ring_px(:small), do: "size-6"
  defp ring_px(:medium), do: "size-8"
  defp ring_px(:large), do: "size-10"

  # Position/width (in %) of an oven's range on a bar spanning its whole scale.
  defp bar_style(%Appliance{} = o) do
    top = Appliance.scale_top(o.temp_unit)
    left = (o.min_temp || 0) / top * 100
    width = max((o.max_temp - (o.min_temp || 0)) / top * 100, 4)
    "left: #{Float.round(left, 1)}%; width: #{Float.round(min(width, 100 - left), 1)}%"
  end

  attr :value, :integer, required: true
  attr :label, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div>
      <div class="text-4xl font-extrabold tabular-nums sm:text-5xl">{@value}</div>
      <div class="mt-1 text-sm font-medium uppercase tracking-wider text-primary-content/70">
        {@label}
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <div class={[
      "pop-in rounded-3xl border border-base-300 bg-base-100/90 p-6 shadow-sm backdrop-blur transition hover:-translate-y-0.5 hover:shadow-lg",
      @class
    ]}>
      <h2 class="flex items-center gap-2 text-sm font-semibold uppercase tracking-wider text-base-content/50">
        <.icon name={@icon} class="size-4" /> {@title}
      </h2>
      <div class="mt-4">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="pop-in relative overflow-hidden rounded-[2rem] bg-gradient-to-br from-primary via-primary to-secondary p-8 text-primary-content shadow-xl shadow-primary/20 sm:p-10">
        <div class="float-slow pointer-events-none absolute -right-10 -top-10 size-56 rounded-full border-[28px] border-white/10">
        </div>
        <div class="float-slow pointer-events-none absolute -bottom-16 right-24 size-40 rounded-full bg-white/10 [animation-delay:-3s]">
        </div>
        <div class="pointer-events-none absolute right-40 top-10 size-14 rounded-full border-8 border-white/15">
        </div>

        <div class="relative flex flex-wrap items-start justify-between gap-4">
          <div>
            <span class="badge border-0 bg-white/20 text-primary-content">
              <.icon name="hero-check-circle" class="size-4" /> Setup complete
            </span>
            <h1 class="mt-4 text-4xl font-extrabold tracking-tight sm:text-5xl">
              Your kitchen is ready
            </h1>
            <p class="mt-3 max-w-md text-primary-content/80">
              Next up: add your dishes and we'll work out what goes where, and when.
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <.link
              id="plan-dishes"
              navigate={~p"/dishes"}
              class="btn rounded-full border-0 bg-white text-primary shadow-lg hover:bg-white/90"
            >
              <.icon name="hero-clock" class="size-4" /> Plan dishes
            </.link>
            <.link
              id="edit-kitchen"
              navigate={~p"/setup"}
              class="btn rounded-full border-0 bg-white/20 text-primary-content backdrop-blur hover:bg-white/30"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit kitchen
            </.link>
          </div>
        </div>

        <div class="relative mt-8 flex gap-10 border-t border-white/20 pt-6">
          <.stat value={length(@ovens)} label={if length(@ovens) == 1, do: "Oven", else: "Ovens"} />
          <.stat value={ring_total(@ring_counts)} label="Hob rings" />
          <.stat value={length(@others)} label="Other" />
        </div>
      </div>

      <div id="summary" class="mt-8 grid gap-4 sm:grid-cols-3">
        <.card icon="hero-fire" title="Ovens" class="[animation-delay:80ms]">
          <p :if={@ovens == []} class="text-sm text-base-content/50">None</p>
          <ul class="space-y-5">
            <li :for={o <- @ovens}>
              <div class="font-semibold">{o.name}</div>
              <div class="relative mt-2 h-2 rounded-full bg-base-200">
                <div
                  class="absolute h-2 rounded-full bg-gradient-to-r from-accent to-primary"
                  style={bar_style(o)}
                >
                </div>
              </div>
              <div class="mt-1.5 text-sm text-base-content/60">{Appliance.temp_range_label(o)}</div>
            </li>
          </ul>
        </.card>

        <.card icon="hero-stop-circle" title="Hob rings" class="[animation-delay:160ms]">
          <p :if={ring_total(@ring_counts) == 0} class="text-sm text-base-content/50">None</p>
          <ul class="space-y-3">
            <li
              :for={size <- Appliance.ring_sizes()}
              :if={@ring_counts[size] > 0}
              class="flex items-center gap-3"
            >
              <span class="flex min-w-24 flex-wrap gap-1.5">
                <span
                  :for={_ <- 1..@ring_counts[size]}
                  class={[
                    ring_px(size),
                    "shrink-0 rounded-full border-4 border-secondary/70 bg-secondary/5"
                  ]}
                ></span>
              </span>
              <span class="text-sm">
                <span class="font-semibold">{@ring_counts[size]}</span>
                <span class="text-base-content/60">{size}</span>
              </span>
            </li>
          </ul>
        </.card>

        <.card icon="hero-bolt" title="Other" class="[animation-delay:240ms]">
          <p :if={@others == []} class="text-sm text-base-content/50">None</p>
          <ul class="flex flex-wrap gap-2">
            <li :for={a <- @others} class="badge badge-lg badge-soft badge-accent">{a.name}</li>
          </ul>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
