defmodule CookingScheduler.Meals.MealDish do
  use Ecto.Schema
  import Ecto.Changeset

  alias CookingScheduler.{Duration, RecipeLink}
  alias CookingScheduler.Kitchen.Appliance

  @methods ~w(oven ring appliance)a
  # When the prep for a dish happens: days ahead (Prep screen) or right before it goes on.
  @prep_days ~w(day_before morning_of before_cooking)a

  # How much of an oven's space a dish takes up, in twelfths so halves, thirds and quarters
  # all add up exactly. The oven holds 12.
  @oven_shares [full: 12, half: 6, third: 4, quarter: 3]

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

    # Live progress while cooking (set from the cook screen, not the planning form).
    field :cook_started_at, :integer
    field :cook_done_at, :integer
    field :extra_minutes, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def methods, do: @methods
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
             appliance_id notes link ingredients_in prepped serve_offset_minutes prep_day next_time)a

  def changeset(dish, attrs) do
    dish
    |> cast(attrs, @fields)
    |> validate_required([:name, :method])
    |> validate_length(:name, max: 80)
    |> RecipeLink.validate(:link)
    |> default_zero([:prep_minutes, :cook_minutes, :rest_minutes])
    |> validate_serve_offset()
    |> validate_by_method()
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
