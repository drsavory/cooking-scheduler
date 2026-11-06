defmodule CookingScheduler.Kitchen.Appliance do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(oven ring other)a
  @temp_units ~w(celsius fahrenheit gas_mark)a
  @ring_sizes ~w(small medium large)a

  schema "appliances" do
    field :kind, Ecto.Enum, values: @kinds, default: :oven
    field :name, :string
    field :temp_unit, Ecto.Enum, values: @temp_units
    field :min_temp, :float
    field :max_temp, :float
    field :size, Ecto.Enum, values: @ring_sizes
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def temp_units, do: @temp_units
  def ring_sizes, do: @ring_sizes

  @doc "A sensible {lowest, highest} setting for a freshly chosen temperature scale."
  def default_range(:celsius), do: {50.0, 250.0}
  def default_range(:fahrenheit), do: {120.0, 480.0}
  def default_range(:gas_mark), do: {0.25, 9.0}

  @doc ~s|e.g. "50 – 250 °C" or "¼ – 9 Gas mark"|
  def temp_range_label(%__MODULE__{min_temp: min, max_temp: max, temp_unit: unit}) do
    "#{fmt_temp(min || 0, unit)} – #{fmt_temp(max, unit)} #{temp_unit_label(unit)}"
  end

  @doc "Formats a setting for display; gas marks use the fractions printed on the dial."
  def fmt_temp(n, unit \\ :celsius)
  def fmt_temp(0.25, :gas_mark), do: "¼"
  def fmt_temp(0.5, :gas_mark), do: "½"
  def fmt_temp(0.75, :gas_mark), do: "¾"
  def fmt_temp(n, _unit) when is_float(n) and n == trunc(n), do: Integer.to_string(trunc(n))
  def fmt_temp(n, _unit), do: to_string(n)

  @doc "Top of the scale used when drawing a temperature range bar."
  def scale_top(:celsius), do: 300
  def scale_top(:fahrenheit), do: 575
  def scale_top(:gas_mark), do: 10

  def temp_unit_label(:celsius), do: "°C"
  def temp_unit_label(:fahrenheit), do: "°F"
  def temp_unit_label(:gas_mark), do: "Gas mark"

  def changeset(appliance, attrs) do
    appliance
    |> cast(attrs, [:kind, :name, :temp_unit, :min_temp, :max_temp, :size, :notes])
    |> validate_required([:kind])
    |> default_ring_name()
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> validate_length(:notes, max: 200)
    |> validate_by_kind()
  end

  # Rings are named from their size ("Medium ring"); Kitchen renumbers them.
  defp default_ring_name(changeset) do
    with :ring <- get_field(changeset, :kind),
         size when not is_nil(size) <- get_field(changeset, :size),
         nil <- get_field(changeset, :name) do
      put_change(changeset, :name, ring_name(size))
    else
      _ -> changeset
    end
  end

  def ring_name(size), do: "#{size |> Atom.to_string() |> String.capitalize()} ring"

  defp validate_by_kind(changeset) do
    case get_field(changeset, :kind) do
      :oven ->
        changeset
        |> validate_required([:temp_unit, :max_temp])
        |> validate_number(:max_temp, greater_than: 0)
        |> validate_number(:min_temp, greater_than_or_equal_to: 0)
        |> validate_gas_mark()
        |> validate_min_below_max()
        |> clear_fields([:size])

      :ring ->
        changeset
        |> validate_required([:size])
        |> clear_fields([:temp_unit, :min_temp, :max_temp])

      _other ->
        clear_fields(changeset, [:temp_unit, :min_temp, :max_temp, :size])
    end
  end

  defp validate_gas_mark(changeset) do
    if get_field(changeset, :temp_unit) == :gas_mark do
      validate_number(changeset, :max_temp,
        less_than_or_equal_to: 10,
        message: "gas marks only go up to 10"
      )
    else
      changeset
    end
  end

  defp validate_min_below_max(changeset) do
    min = get_field(changeset, :min_temp)
    max = get_field(changeset, :max_temp)

    if min && max && min > max do
      add_error(changeset, :min_temp, "must not be higher than the maximum")
    else
      changeset
    end
  end

  defp clear_fields(changeset, fields) do
    Enum.reduce(fields, changeset, &put_change(&2, &1, nil))
  end
end
