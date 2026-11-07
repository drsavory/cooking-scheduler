defmodule CookingScheduler.Meals.SavedDish do
  @moduledoc """
  A reusable dish in the library. Each meal's dish starts as a copy of one of these
  (so this year's turkey can differ from last year's) and keeps a link back to it,
  which is how we know every meal a dish has been used in.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CookingScheduler.Duration
  alias CookingScheduler.Kitchen.Appliance

  # The planning values that get copied between a saved dish and a meal's dish.
  @template ~w(name method ring_size temp temp_unit prep_minutes cook_minutes buffer_minutes
               rest_minutes notes link)a

  schema "saved_dishes" do
    field :name, :string
    field :method, Ecto.Enum, values: [:oven, :ring, :appliance]
    field :ring_size, Ecto.Enum, values: Appliance.ring_sizes()
    field :temp, :float
    field :temp_unit, Ecto.Enum, values: Appliance.temp_units()
    field :prep_minutes, Duration, default: 0
    field :cook_minutes, Duration, default: 0
    field :buffer_minutes, Duration, default: 0
    field :rest_minutes, Duration, default: 0
    field :notes, :string
    field :link, :string

    has_many :dishes, CookingScheduler.Meals.Dish
    has_many :dish_ingredients, CookingScheduler.Meals.DishIngredient

    timestamps(type: :utc_datetime)
  end

  def template_fields, do: @template

  def changeset(saved, attrs) do
    saved
    |> cast(attrs, @template)
    |> validate_required([:name, :method])
    |> validate_length(:name, max: 80)
    |> validate_by_method()
  end

  # Mirrors `Dish`, so a saved dish can always be copied into a meal.
  defp validate_by_method(changeset) do
    case get_field(changeset, :method) do
      :oven ->
        changeset
        |> validate_required([:temp, :temp_unit])
        |> validate_number(:temp, greater_than: 0)
        |> put_change(:ring_size, nil)

      :ring ->
        changeset
        |> validate_required([:ring_size])
        |> put_change(:temp, nil)
        |> put_change(:temp_unit, nil)

      _ ->
        changeset
        |> put_change(:ring_size, nil)
        |> put_change(:temp, nil)
        |> put_change(:temp_unit, nil)
    end
  end
end
