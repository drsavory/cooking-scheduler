defmodule CookingScheduler.Meals.MealDish do
  use Ecto.Schema
  import Ecto.Changeset

  alias CookingScheduler.{Duration, RecipeLink, UnitConversion}
  alias CookingScheduler.Kitchen.Appliance

  @methods ~w(oven ring appliance)a
  # When the prep for a dish happens: days ahead (Prep screen) or right before it goes on.
  @prep_days ~w(day_before morning_of before_cooking)a

  # How much of an oven's space a dish takes up, in twelfths so halves, thirds and quarters
  # all add up exactly. The oven holds 12.
  @oven_shares [full: 12, half: 6, third: 4, quarter: 3]

  # Sized dishes (ADR 0029): the weight unit a cook-time rule is written in.
  @size_units ~w(kg lb)a

  schema "meal_dishes" do
    field :name, :string
    field :method, Ecto.Enum, values: @methods, default: :oven
    field :prep_minutes, Duration, default: 0
    field :cook_minutes, Duration, default: 0
    field :rest_minutes, Duration, default: 0
    field :temp, :float
    field :temp_unit, Ecto.Enum, values: Appliance.temp_units()
    field :ring_size, Ecto.Enum, values: Appliance.ring_sizes()
    field :oven_share, Ecto.Enum, values: Keyword.keys(@oven_shares), default: :third
    belongs_to :appliance, Appliance
    belongs_to :meal, CookingScheduler.Meals.Meal
    belongs_to :dish, CookingScheduler.Meals.Dish
    has_many :dish_ingredients, CookingScheduler.Meals.DishIngredient
    # Courses: minutes after (or, negative, before) the meal's serving time this dish is
    # ready. 0 means with the main.
    field :serve_offset_minutes, :integer, default: 0
    field :prep_day, Ecto.Enum, values: @prep_days, default: :before_cooking
    field :notes, :string
    field :link, :string
    field :ingredients_in, :boolean, default: false
    field :prepped, :boolean, default: false
    # Written after the meal: what to change next time.
    field :next_time, :string

    # Sized dishes (ADR 0029): a cook time worked out from weight, copied from the dish,
    # plus this one's own weight (in `size_unit`). Changing the weight resets the cook time.
    field :size_unit, Ecto.Enum, values: @size_units
    field :minutes_per_size, Duration
    field :base_minutes, Duration, default: 0
    field :size, :float

    # Done when the inside reaches this (a probe reading), in °C or °F. Any method.
    field :done_temp, :float
    field :done_temp_unit, Ecto.Enum, values: [:celsius, :fahrenheit]

    # Live progress while cooking (set from the cook screen, not the planning form).
    field :cook_started_at, :integer
    field :cook_done_at, :integer
    field :extra_minutes, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def methods, do: @methods
  def size_units, do: @size_units

  @doc "Weight units as `{label, value}` pairs for a select."
  def size_unit_options, do: for(u <- @size_units, do: {Atom.to_string(u), u})

  @doc "Whether the dish's cook time is worked out from its weight."
  def sized?(%{minutes_per_size: per}), do: is_integer(per) and per > 0

  @doc """
  Cook minutes for a sized dish at `size`, by its rule: `base + per × size`, rounded to the
  minute. `nil` for a dish without a rule or without a weight.
  """
  def cook_for_size(%{minutes_per_size: per, base_minutes: base} = dish, size)
      when is_number(size) do
    if sized?(dish), do: (base || 0) + round(per * size)
  end

  def cook_for_size(_dish, _size), do: nil

  @doc ~s|A weight for display: `5.2` and `:kg` -> "5.2 kg"; whole numbers drop the ".0".|
  def size_text(nil, _unit), do: nil
  def size_text(size, unit), do: "#{size_number(size)} #{unit || :kg}"

  @doc ~s|A weight as a number to type over: `5.0` -> "5", `5.25` -> "5.25".|
  def size_number(size) do
    size = Float.round(size * 1.0, 2)
    if size == Float.round(size), do: Integer.to_string(trunc(size)), else: Float.to_string(size)
  end

  @doc ~s|A sized dish's rule for display: "40m per kg + 20m".|
  def rule_text(%{minutes_per_size: per, base_minutes: base, size_unit: unit} = dish) do
    if sized?(dish) do
      plus = if (base || 0) > 0, do: " + #{Duration.format(base)}", else: ""
      "#{Duration.format(per)} per #{unit || :kg}#{plus}"
    end
  end

  def prep_days, do: @prep_days

  @doc "Prep timings as `{label, value}` pairs for a select."
  def prep_day_options,
    do: [
      {"Just before cooking", :before_cooking},
      {"Morning of", :morning_of},
      {"Day before", :day_before}
    ]

  @doc "Common course offsets as `{label, minutes}` pairs; anything else is \"custom\"."
  def serve_offset_options,
    do: [
      {"Starter · 45m before", -45},
      {"With the main", 0},
      {"Pudding · 45m after", 45},
      {"Pudding · 1h after", 60},
      {"Cheese · 1h 30m after", 90}
    ]

  @doc ~s|"Starter", "Main" or "Pudding" from a serving offset.|
  def course(offset) when offset < 0, do: "Starter"
  def course(0), do: "Main"
  def course(_), do: "Pudding"

  @doc "Oven shares as `{label, value}` pairs for a select."
  def oven_share_options,
    do: [{"Whole oven", :full}, {"Half", :half}, {"Third", :third}, {"Quarter", :quarter}]

  @doc "Total space in an oven, in the same units as `oven_units/1`."
  def oven_capacity, do: 12

  @doc "How many twelfths of an oven a share takes up."
  def oven_units(share), do: Keyword.fetch!(@oven_shares, share || :third)

  @fields ~w(name method prep_minutes cook_minutes rest_minutes temp temp_unit ring_size oven_share
             appliance_id notes link ingredients_in prepped serve_offset_minutes prep_day next_time
             size_unit minutes_per_size base_minutes size done_temp done_temp_unit)a

  def changeset(dish, attrs) do
    dish
    |> cast(attrs, @fields)
    |> validate_required([:name, :method])
    |> validate_length(:name, max: 80)
    |> RecipeLink.validate(:link)
    |> default_zero([:prep_minutes, :cook_minutes, :rest_minutes, :base_minutes])
    |> validate_serve_offset()
    |> validate_sizing()
    |> validate_done_temp()
    |> validate_number(:size, greater_than: 0, less_than: 100)
    |> cook_from_size()
    |> validate_by_method()
  end

  @doc """
  Shared with `Dish`: a cook-time rule needs a unit, and a blank rule means "not sized".
  """
  def validate_sizing(changeset) do
    changeset
    |> update_change(:base_minutes, &(&1 || 0))
    |> validate_number(:minutes_per_size, greater_than: 0, less_than_or_equal_to: 600)
    |> then(fn cs ->
      if get_field(cs, :minutes_per_size) && is_nil(get_field(cs, :size_unit)),
        do: put_change(cs, :size_unit, :kg),
        else: cs
    end)
  end

  @doc """
  Shared with `Dish`: an inside temperature is a probe reading in °C or °F, °C unless said.
  """
  def validate_done_temp(changeset) do
    case get_field(changeset, :done_temp) do
      nil ->
        put_change(changeset, :done_temp_unit, nil)

      _ ->
        changeset =
          if get_field(changeset, :done_temp_unit),
            do: changeset,
            else: put_change(changeset, :done_temp_unit, :celsius)

        max = if get_field(changeset, :done_temp_unit) == :fahrenheit, do: 450, else: 230

        validate_number(changeset, :done_temp,
          greater_than: 0,
          less_than_or_equal_to: max,
          message: "should be a probe reading, like 74"
        )
    end
  end

  @doc "Inside-temperature units as `{label, value}` pairs for a select."
  def done_temp_unit_options, do: [{"°C", :celsius}, {"°F", :fahrenheit}]

  @doc ~s|"74°C · 165°F inside", or nil when there's no inside temperature.|
  def done_temp_text(%{done_temp: nil}), do: nil

  def done_temp_text(%{done_temp: t, done_temp_unit: unit}) do
    unit = unit || :celsius
    other = if unit == :celsius, do: :fahrenheit, else: :celsius
    converted = UnitConversion.convert!(t, unit, other, round: 0)
    "#{degrees(t, unit)} · #{degrees(converted, other)} inside"
  end

  defp degrees(t, unit), do: "#{round(t)}#{if unit == :celsius, do: "°C", else: "°F"}"

  # A new weight (or rule) sets the cook time, unless the cook time was typed in the same go.
  defp cook_from_size(changeset) do
    moved? = Enum.any?([:size, :minutes_per_size, :base_minutes], &changed?(changeset, &1))

    with true <- changeset.valid? and moved? and not changed?(changeset, :cook_minutes),
         minutes when is_integer(minutes) <-
           cook_for_size(apply_changes(changeset), get_field(changeset, :size)) do
      put_change(changeset, :cook_minutes, minutes)
    else
      _ -> changeset
    end
  end

  @doc "Shared with `Dish`: a course offset is within a few hours either side of the meal."
  def validate_serve_offset(changeset) do
    changeset
    |> update_change(:serve_offset_minutes, &(&1 || 0))
    |> validate_number(:serve_offset_minutes,
      greater_than_or_equal_to: -360,
      less_than_or_equal_to: 360,
      message: "keep courses within 6 hours of the meal"
    )
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
        greater_than_or_equal_to: 0.25,
        less_than_or_equal_to: 10,
        message: "gas marks go from ¼ to 10"
      )
    else
      changeset
    end
  end
end
