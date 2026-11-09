defmodule CookingScheduler.Meals.Ingredient do
  @moduledoc "A shared ingredient (e.g. butter) that any number of dishes can use."
  use Ecto.Schema
  import Ecto.Changeset

  # Shop aisles, in the order a shop is usually laid out.
  @categories ~w(veg meat_fish dairy bakery cupboard frozen drinks)a

  schema "ingredients" do
    field :name, :string
    # Always in the cupboard (salt, oil): shown under "check the cupboard", not the buy list.
    field :staple, :boolean, default: false
    field :category, Ecto.Enum, values: @categories
    timestamps(type: :utc_datetime)
  end

  def categories, do: @categories

  @doc "Aisle categories as `{label, value}` pairs for a select."
  def category_options,
    do: [
      {"Fruit & veg", :veg},
      {"Meat & fish", :meat_fish},
      {"Dairy & eggs", :dairy},
      {"Bakery", :bakery},
      {"Cupboard", :cupboard},
      {"Frozen", :frozen},
      {"Drinks", :drinks}
    ]

  def category_label(nil), do: "Not filed yet"

  def category_label(category),
    do: Enum.find_value(category_options(), fn {l, v} -> v == category && l end)

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name, :staple, :category])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name, name: :ingredients_lower_name_index)
  end
end
