defmodule CookingSchedulerWeb.DishFormLive do
  @moduledoc """
  Create a dish (a library dish) to reuse in future meals. Existing dishes are edited in place
  on `DishLive`.

  Rendered two ways: as its own page at `/dishes/new`, or nested inside the Plan screen's
  "Add a dish" modal (`live_render` with a `"meal_id"` in the session). Nested, it has no
  layout, saving also adds the dish to that meal, and it reports back to the parent with
  `{:new_dish, dish, result}` or `:close_add_dish`.
  """
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Duration, Meals}
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.Dish

  @impl true
  def mount(_params, session, socket) do
    dish = %Dish{method: :oven, temp_unit: :gas_mark}

    meal =
      case session do
        %{"meal_id" => id} -> Meals.get_meal!(id)
        _ -> nil
      end

    {:ok,
     socket
     |> assign(:page_title, "New dish")
     |> assign(:meal, meal)
     |> assign(:dish, dish)
     |> assign(:form, to_form(Meals.change_dish(dish)))}
  end

  @impl true
  def handle_event("validate", %{"dish" => params}, socket) do
    form = socket.assigns.dish |> Meals.change_dish(params) |> to_form(action: :validate)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"dish" => params}, socket) do
    case Meals.create_dish(params) do
      {:ok, dish} -> {:noreply, after_save(socket, dish)}
      {:error, changeset} -> {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel", _params, socket) do
    if socket.parent_pid, do: send(socket.parent_pid, :close_add_dish)
    {:noreply, socket}
  end

  defp after_save(%{assigns: %{meal: nil}} = socket, dish),
    do: push_navigate(socket, to: ~p"/dishes/#{dish.id}")

  defp after_save(%{assigns: %{meal: meal}} = socket, dish) do
    send(socket.parent_pid, {:new_dish, dish, Meals.add_dish_to_meal(meal, dish)})
    socket
  end

  defp method(form), do: Ecto.Changeset.get_field(form.source, :method)

  defp duration_value(v) when is_integer(v), do: Duration.format(v)
  defp duration_value(v), do: v

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil

  defp duration(assigns) do
    ~H"""
    <.input
      type="text"
      id={@field.id}
      name={@field.name}
      value={duration_value(@field.value)}
      errors={Enum.map(@field.errors, &translate_error/1)}
      label={@label}
      placeholder={@placeholder || "1:30"}
      phx-debounce="400"
    />
    """
  end

  attr :form, :any, required: true
  attr :embedded, :boolean, required: true

  defp dish_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="dish-form"
      phx-change="validate"
      phx-submit="save"
      class={[
        !@embedded && "mt-6 rounded-3xl border border-base-300 bg-base-100/90 p-6 shadow-sm"
      ]}
    >
      <.input
        field={@form[:name]}
        type="text"
        label="Name"
        phx-debounce="400"
        phx-mounted={@embedded && JS.focus()}
      />

      <div class="mb-4">
        <span class="mb-1 block text-sm font-semibold">Tags</span>
        <.tag_picker
          field={@form[:tags]}
          custom={@form[:custom_tags]}
          suggested={Dish.suggested_tags()}
        />
      </div>

      <.input
        field={@form[:method]}
        type="select"
        label="Cooked in"
        options={[{"Oven", :oven}, {"Hob", :ring}, {"Slow cooker / grill / other", :appliance}]}
      />

      <div :if={method(@form) == :oven} class="grid gap-x-4 sm:grid-cols-2">
        <.input field={@form[:temp]} type="number" step="any" label="Temperature" />
        <.input
          field={@form[:temp_unit]}
          type="select"
          label="Scale"
          options={for u <- Appliance.temp_units(), do: {Appliance.temp_unit_label(u), u}}
        />
      </div>

      <.input
        :if={method(@form) == :oven}
        field={@form[:oven_share]}
        type="select"
        label="Oven space"
        options={CookingScheduler.Meals.MealDish.oven_share_options()}
      />

      <.input
        :if={method(@form) == :ring}
        field={@form[:ring_size]}
        type="select"
        label="Ring size"
        prompt="Choose…"
        options={[{"Small", :small}, {"Medium", :medium}, {"Large", :large}]}
      />

      <div class="grid grid-cols-3 gap-x-4">
        <.duration field={@form[:prep_minutes]} label="Prep" />
        <.duration field={@form[:cook_minutes]} label="Cook" />
        <.duration field={@form[:rest_minutes]} label="Rest" />
      </div>

      <.input field={@form[:notes]} type="textarea" rows="2" label="Notes" phx-debounce="400" />
      <.input
        field={@form[:link]}
        type="text"
        label="Recipe link"
        placeholder="https://…"
        phx-debounce="400"
      />

      <div class="mt-2 flex justify-end gap-2">
        <button
          :if={@embedded}
          id="cancel-dish"
          type="button"
          class="btn btn-ghost rounded-full"
          phx-click="cancel"
        >
          Cancel
        </button>
        <.link :if={!@embedded} navigate={~p"/"} class="btn btn-ghost rounded-full">Cancel</.link>
        <button id="save-dish" type="submit" class="btn btn-primary rounded-full">
          <.icon name="hero-check" class="size-4" />
          {if @embedded, do: "Save & add to meal", else: "Save dish"}
        </button>
      </div>
    </.form>
    """
  end

  @impl true
  def render(%{meal: %Meals.Meal{}} = assigns) do
    ~H"""
    <.dish_form form={@form} embedded={true} />
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        navigate={~p"/"}
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> Home
      </.link>
      <h1 class="text-3xl font-extrabold tracking-tight sm:text-4xl">New dish</h1>
      <p class="mt-1 text-base-content/60">
        A dish idea you can drop into any future meal. Each meal gets its own copy.
      </p>

      <.dish_form form={@form} embedded={false} />
    </Layouts.app>
    """
  end
end
