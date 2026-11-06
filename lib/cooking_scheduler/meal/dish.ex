defmodule CookingScheduler.Meal.Dish do
  use Ecto.Schema
  import Ecto.Changeset

  alias CookingScheduler.Duration
  alias CookingScheduler.Kitchen.Appliance

  @methods ~w(oven ring appliance)a

  schema "dishes" do
    field :name, :string
    field :method, Ecto.Enum, values: @methods, default: :oven
    field :prep_minutes, Duration, default: 0
    field :cook_minutes, Duration, default: 0
    field :buffer_minutes, Duration, default: 0
    field :rest_minutes, Duration, default: 0
    field :temp, :float
    field :temp_unit, Ecto.Enum, values: Appliance.temp_units()
    field :ring_size, Ecto.Enum, values: Appliance.ring_sizes()
    belongs_to :appliance, Appliance
    field :notes, :string
    field :link, :string
    field :ingredients_in, :boolean, default: false
    field :prepped, :boolean, default: false

    # Live progress while cooking (set from the cook screen, not the planning form).
    field :cook_started_at, :integer
    field :cook_done_at, :integer
    field :extra_minutes, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def methods, do: @methods

  @fields ~w(name method prep_minutes cook_minutes buffer_minutes rest_minutes temp temp_unit ring_size
             appliance_id notes link ingredients_in prepped)a

  def changeset(dish, attrs) do
    dish
    |> cast(attrs, @fields)
    |> validate_required([:name, :method])
    |> validate_length(:name, max: 80)
    |> default_zero([:prep_minutes, :cook_minutes, :buffer_minutes, :rest_minutes])
    |> validate_by_method()
  end

  # Blank durations mean "none", not "missing".
  defp default_zero(changeset, fields) do
    Enum.reduce(fields, changeset, fn f, cs ->
      if get_field(cs, f) == nil, do: put_change(cs, f, 0), else: cs
    end)
  end

  defp validate_by_method(changeset) do
    case get_field(changeset, :method) do
      :oven ->
        changeset
        |> validate_required([:temp, :temp_unit])
        |> validate_number(:temp, greater_than: 0)
        |> validate_gas_mark()
        |> put_change(:ring_size, nil)

      :ring ->
        changeset
        |> validate_required([:ring_size])
        |> put_change(:appliance_id, nil)
        |> put_change(:temp, nil)
        |> put_change(:temp_unit, nil)

      _appliance ->
        changeset
        |> put_change(:ring_size, nil)
        |> put_change(:temp, nil)
        |> put_change(:temp_unit, nil)
    end
  end

  defp validate_gas_mark(changeset) do
    if get_field(changeset, :temp_unit) == :gas_mark do
      validate_number(changeset, :temp,
        less_than_or_equal_to: 10,
        message: "gas marks only go up to 10"
      )
    else
      changeset
    end
  end
end
