defmodule CookingSchedulerWeb.SetupLive do
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.Kitchen
  alias CookingScheduler.Kitchen.Appliance

  @max_rings 8
  @quick_adds ["Slow cooker", "Air fryer", "Microwave", "Toaster oven"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Set up your kitchen") |> assign(:invalid, %{}) |> load()}
  end

  defp load(socket) do
    socket
    |> assign(:appliances, Kitchen.list_appliances())
    |> assign(:ring_counts, Kitchen.ring_counts())
  end

  @impl true
  def handle_event("add_oven", %{"unit" => unit}, socket) do
    if unit = Enum.find(Appliance.temp_units(), &(Atom.to_string(&1) == unit)) do
      {:ok, _} = Kitchen.add_oven(unit)
    end

    {:noreply, load(socket)}
  end

  def handle_event("add_other", %{"name" => name}, socket) do
    {:ok, _} = Kitchen.add_other(name)
    {:noreply, load(socket)}
  end

  def handle_event("ring", %{"size" => size, "delta" => delta}, socket) do
    size = Enum.find(Appliance.ring_sizes(), &(Atom.to_string(&1) == size))
    delta = String.to_integer(delta)
    count = size && socket.assigns.ring_counts[size]

    if size && delta in [1, -1] && (delta == 1 || count > 0) &&
         (delta == -1 || count < @max_rings) do
      {:ok, _} = Kitchen.adjust_rings(size, delta)
    end

    {:noreply, load(socket)}
  end

  # Cards are always-editable forms: every change is saved as soon as it's valid.
  def handle_event("update", %{"appliance_id" => id, "appliance" => params}, socket) do
    appliance = Kitchen.get_appliance!(id)
    params = apply_scale_defaults(appliance, params)
    changeset = Kitchen.change_appliance(appliance, params)

    if changeset.valid? do
      {:ok, _} = Kitchen.update_appliance(appliance, params)
      {:noreply, socket |> update(:invalid, &Map.delete(&1, appliance.id)) |> load()}
    else
      form = to_form(%{changeset | action: :validate}, id: form_id(appliance))
      {:noreply, update(socket, :invalid, &Map.put(&1, appliance.id, form))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Kitchen.get_appliance!() |> Kitchen.delete_appliance()
    {:noreply, socket |> update(:invalid, &Map.delete(&1, String.to_integer(id))) |> load()}
  end

  # Switching scale (e.g. °C -> gas mark) resets the range to that scale's defaults,
  # otherwise 250 would be an invalid gas mark.
  defp apply_scale_defaults(
         %Appliance{kind: :oven, temp_unit: current},
         %{"temp_unit" => unit} = params
       )
       when is_binary(unit) do
    case Enum.find(Appliance.temp_units(), &(Atom.to_string(&1) == unit)) do
      new when new != nil and new != current ->
        {min, max} = Appliance.default_range(new)
        Map.merge(params, %{"min_temp" => to_string(min), "max_temp" => to_string(max)})

      _ ->
        params
    end
  end

  defp apply_scale_defaults(_appliance, params), do: params

  defp form_id(%Appliance{id: id}), do: "appliance-#{id}"

  defp card_form(%Appliance{} = a, invalid) do
    Map.get(invalid, a.id) || to_form(Kitchen.change_appliance(a), id: form_id(a))
  end

  defp kind_icon(:oven), do: "hero-fire"
  defp kind_icon(:ring), do: "hero-stop-circle"
  defp kind_icon(:other), do: "hero-bolt"

  defp size_label(size), do: size |> Atom.to_string() |> String.capitalize()

  defp size_hint(:small), do: "Simmering, sauces"
  defp size_hint(:medium), do: "Everyday pans"
  defp size_hint(:large), do: "Big pots, boiling"

  defp ring_px(:small), do: "size-7"
  defp ring_px(:medium), do: "size-9"
  defp ring_px(:large), do: "size-11"

  defp ring_order(ring),
    do: {Enum.find_index(Appliance.ring_sizes(), &(&1 == ring.size)), ring.id}

  attr :kind, :atom, required: true

  defp kind_badge(assigns) do
    ~H"""
    <span class={[
      "grid size-11 shrink-0 place-items-center rounded-2xl",
      @kind == :oven && "bg-gradient-to-br from-primary/20 to-accent/30 text-primary",
      @kind == :ring && "bg-gradient-to-br from-secondary/20 to-secondary/5 text-secondary",
      @kind == :other && "bg-gradient-to-br from-accent/40 to-accent/10 text-accent-content"
    ]}>
      <.icon name={kind_icon(@kind)} class="size-6" />
    </span>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :kind, :atom, required: true
  slot :actions
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section class="pop-in mt-12">
      <div class="mb-4 flex items-center justify-between gap-4">
        <div class="flex items-center gap-3">
          <.kind_badge kind={@kind} />
          <div>
            <h2 class="text-lg font-semibold leading-tight">{@title}</h2>
            <p class="text-sm text-base-content/60">{@subtitle}</p>
          </div>
        </div>
        {render_slot(@actions)}
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :appliance, Appliance, required: true
  attr :form, :any, required: true

  defp appliance_card(assigns) do
    ~H"""
    <li
      id={"appliance-card-#{@appliance.id}"}
      class="pop-in rounded-3xl border border-base-300 bg-base-100/90 p-5 shadow-sm backdrop-blur transition hover:shadow-lg hover:shadow-primary/5"
    >
      <.form for={@form} id={@form.id <> "-form"} phx-change="update">
        <input type="hidden" name="appliance_id" value={@appliance.id} />
        <div class="flex items-start gap-3">
          <div class="flex-1">
            <.input
              field={@form[:name]}
              type="text"
              aria-label="Name"
              class="input w-full text-lg font-semibold"
              phx-debounce="400"
            />
          </div>
          <button
            type="button"
            class="btn btn-sm btn-circle btn-ghost mt-1.5 hover:text-error"
            phx-click="delete"
            phx-value-id={@appliance.id}
            aria-label={"Remove #{@appliance.name}"}
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>

        <div :if={@appliance.kind == :oven} class="grid gap-x-4 sm:grid-cols-3">
          <.input
            field={@form[:temp_unit]}
            type="select"
            label="Scale"
            options={[
              {"Celsius (°C)", :celsius},
              {"Fahrenheit (°F)", :fahrenheit},
              {"Gas mark", :gas_mark}
            ]}
          />
          <.input field={@form[:min_temp]} type="number" step="any" label="Lowest" phx-debounce="500" />
          <.input
            field={@form[:max_temp]}
            type="number"
            step="any"
            label="Highest"
            phx-debounce="500"
          />
        </div>

        <.input
          :if={@appliance.kind == :other}
          field={@form[:notes]}
          type="text"
          placeholder="Notes, e.g. 6.5L, fits a turkey crown"
          aria-label="Notes"
          phx-debounce="400"
        />
      </.form>
    </li>
    """
  end

  attr :text, :string, required: true

  defp empty(assigns) do
    ~H"""
    <p class="rounded-3xl border border-dashed border-base-300 px-6 py-8 text-center text-sm text-base-content/50">
      {@text}
    </p>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        ovens: Enum.filter(assigns.appliances, &(&1.kind == :oven)),
        others: Enum.filter(assigns.appliances, &(&1.kind == :other)),
        rings:
          assigns.appliances |> Enum.filter(&(&1.kind == :ring)) |> Enum.sort_by(&ring_order/1),
        max_rings: @max_rings,
        quick_adds: @quick_adds
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <div>
        <span class="badge badge-primary badge-soft mb-3 gap-1.5">
          <.icon name="hero-sparkles" class="size-3.5" /> Let's get cooking
        </span>
        <h1 class="bg-gradient-to-r from-primary to-secondary bg-clip-text text-4xl font-extrabold tracking-tight text-transparent sm:text-5xl">
          Set up your kitchen
        </h1>
        <p class="mt-2 max-w-md text-base-content/60">
          Tell us what you're cooking with so we can plan what goes where.
          Changes save as you go.
        </p>
      </div>

      <.section kind={:oven} title="Ovens" subtitle="Tap the scale your oven uses">
        <:actions>
          <div id="add-oven" class="flex flex-wrap justify-end gap-2">
            <button
              :for={{unit, label} <- [celsius: "°C", gas_mark: "Gas mark", fahrenheit: "°F"]}
              class="btn btn-sm rounded-full"
              phx-click="add_oven"
              phx-value-unit={unit}
            >
              <.icon name="hero-plus" class="size-4" /> {label} oven
            </button>
          </div>
        </:actions>
        <.empty :if={@ovens == []} text="No ovens yet. Add your first one." />
        <ul :if={@ovens != []} class="grid gap-4">
          <.appliance_card :for={a <- @ovens} appliance={a} form={card_form(a, @invalid)} />
        </ul>
      </.section>

      <.section
        kind={:ring}
        title="Hob rings"
        subtitle="Each ring is used by one pan at a time, so count them individually"
      >
        <div
          id="rings"
          class="rounded-3xl border border-base-300 bg-base-100/90 p-5 shadow-sm backdrop-blur"
        >
          <div class="divide-y divide-base-300">
            <div
              :for={size <- Appliance.ring_sizes()}
              id={"rings-#{size}"}
              class="flex items-center gap-4 py-3 first:pt-0 last:pb-0"
            >
              <div class="grid w-12 place-items-center">
                <span class={[
                  ring_px(size),
                  "grid place-items-center rounded-full border-[5px] border-secondary/70 bg-secondary/5"
                ]}>
                  <span class="size-1.5 rounded-full bg-secondary/60"></span>
                </span>
              </div>
              <div class="flex-1">
                <div class="font-medium">{size_label(size)}</div>
                <div class="text-sm text-base-content/60">{size_hint(size)}</div>
              </div>
              <div class="flex items-center gap-2">
                <button
                  class="btn btn-sm btn-circle transition active:scale-90"
                  phx-click="ring"
                  phx-value-size={size}
                  phx-value-delta="-1"
                  disabled={@ring_counts[size] == 0}
                  aria-label={"Fewer #{size} rings"}
                >
                  <.icon name="hero-minus" class="size-4" />
                </button>
                <span id={"count-#{size}"} class="w-6 text-center text-lg font-semibold tabular-nums">
                  {@ring_counts[size]}
                </span>
                <button
                  class="btn btn-sm btn-circle transition active:scale-90"
                  phx-click="ring"
                  phx-value-size={size}
                  phx-value-delta="1"
                  disabled={@ring_counts[size] >= @max_rings}
                  aria-label={"More #{size} rings"}
                >
                  <.icon name="hero-plus" class="size-4" />
                </button>
              </div>
            </div>
          </div>

          <div
            :if={@rings != []}
            class="mt-5 flex flex-wrap items-end gap-2 border-t border-base-300 pt-5"
          >
            <span
              :for={ring <- @rings}
              id={"ring-#{ring.id}"}
              title={ring.name}
              class={[ring_px(ring.size), "rounded-full border-[5px] border-secondary/70"]}
            ></span>
            <span class="ml-2 self-center text-sm text-base-content/60">
              {length(@rings)} {if length(@rings) == 1, do: "ring", else: "rings"} in total
            </span>
          </div>
        </div>
      </.section>

      <.section
        kind={:other}
        title="Other appliances"
        subtitle="Slow cookers, air fryers, microwaves…"
      >
        <div id="quick-add" class="mb-4 flex flex-wrap gap-2">
          <button
            :for={name <- @quick_adds}
            class="btn btn-sm rounded-full"
            phx-click="add_other"
            phx-value-name={name}
          >
            <.icon name="hero-plus" class="size-4" /> {name}
          </button>
          <button
            class="btn btn-sm btn-ghost rounded-full"
            phx-click="add_other"
            phx-value-name="New appliance"
          >
            <.icon name="hero-plus" class="size-4" /> Something else
          </button>
        </div>
        <.empty :if={@others == []} text="Nothing else yet. Tap one above to add it." />
        <ul :if={@others != []} class="grid gap-4 sm:grid-cols-2">
          <.appliance_card :for={a <- @others} appliance={a} form={card_form(a, @invalid)} />
        </ul>
      </.section>

      <div class="mt-12 flex items-center justify-end gap-4 border-t border-base-300 pt-6">
        <p :if={@appliances == []} class="text-sm text-base-content/60">
          Add at least one oven, ring or appliance to continue.
        </p>
        <.link
          :if={@appliances != []}
          id="finished"
          navigate={~p"/"}
          class="btn btn-primary btn-lg group rounded-full border-0 bg-gradient-to-r from-primary to-secondary px-8 shadow-lg shadow-primary/30 transition hover:scale-[1.03] hover:shadow-xl"
        >
          Finished
          <.icon name="hero-arrow-right" class="size-5 transition group-hover:translate-x-1" />
        </.link>
        <button :if={@appliances == []} class="btn btn-lg rounded-full px-8" disabled>
          Finished <.icon name="hero-arrow-right" class="size-5" />
        </button>
      </div>
    </Layouts.app>
    """
  end
end
