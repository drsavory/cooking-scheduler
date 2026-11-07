defmodule CookingScheduler.Meals.ShoppingCheck do
  @moduledoc "An ingredient ticked off a meal's shopping list (bought). No row means still to buy."
  use Ecto.Schema

  schema "shopping_checks" do
    belongs_to :meal, CookingScheduler.Meals.Meal
    belongs_to :ingredient, CookingScheduler.Meals.Ingredient
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
