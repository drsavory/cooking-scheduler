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
  @template ~w(name method ring_size oven_share temp temp_unit prep_minutes cook_minutes buffer_minutes
               rest_minutes notes link)a

  schema "saved_dishes" do
    field :name, :string
    field :method, Ecto.Enum, values: [:oven, :ring, :appliance]
    field :ring_size, Ecto.Enum, values: Appliance.ring_sizes()
    field :oven_share, Ecto.Enum, values: [:full, :half, :third, :quarter], default: :third
    field :temp, :float
    field :temp_unit, Ecto.Enum, values: Appliance.temp_units()
    field :prep_minutes, Duration, default: 0
    field :cook_minutes, Duration, default: 0
    field :buffer_minutes, Duration, default: 0
    field :rest_minutes, Duration, default: 0
    field :notes, :string
    field :link, :string
    # Free-form labels ("protein", "veg", ...). Library-only: not copied into meals.
    field :tags, {:array, :string}, default: []
    # Form input: extra comma-separated tags, merged into `tags` on save.
    field :custom_tags, :string, virtual: true

    has_many :dishes, CookingScheduler.Meals.Dish
    has_many :dish_ingredients, CookingScheduler.Meals.DishIngredient

    timestamps(type: :utc_datetime)
  end

  def template_fields, do: @template

  @suggested_tags ~w(main protein veg carbs side starter dessert sauce)

  @doc "Tags offered as one-tap choices; anyone can add their own too."
  def suggested_tags, do: @suggested_tags

  def changeset(saved, attrs) do
    saved
    |> cast(attrs, @template ++ [:tags, :custom_tags])
    |> merge_tags()
    |> validate_required([:name, :method])
    |> validate_length(:name, max: 80)
    |> validate_by_method()
  end

  # Tidies the picked tags and folds in any typed ones: lowercase, trimmed, no blanks or repeats.
  defp merge_tags(changeset) do
    typed = changeset |> get_change(:custom_tags, "") |> String.split(",")

    tags =
      (get_field(changeset, :tags) ++ typed)
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    changeset
    |> put_change(:tags, tags)
    |> delete_change(:custom_tags)
    |> validate_change(:tags, fn :tags, tags ->
      if Enum.any?(tags, &(String.length(&1) > 24)),
        do: [tags: "must be 24 characters or fewer each"],
        else: []
    end)
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
