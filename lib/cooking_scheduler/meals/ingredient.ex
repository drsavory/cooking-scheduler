defmodule CookingScheduler.Meals.Ingredient do
  @moduledoc "A shared ingredient (e.g. butter) that any number of dishes can use."
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :name, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name, name: :ingredients_lower_name_index)
  end
end
