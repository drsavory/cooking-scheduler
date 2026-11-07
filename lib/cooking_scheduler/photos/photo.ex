defmodule CookingScheduler.Photos.Photo do
  @moduledoc "A picture of a meal or of one dish in a meal. The bytes live in `CookingScheduler.Storage`."
  use Ecto.Schema

  schema "photos" do
    field :key, :string
    field :content_type, :string
    field :byte_size, :integer
    field :filename, :string
    belongs_to :meal, CookingScheduler.Meals.Meal
    belongs_to :meal_dish, CookingScheduler.Meals.MealDish

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
