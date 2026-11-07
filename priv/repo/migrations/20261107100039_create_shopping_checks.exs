defmodule CookingScheduler.Repo.Migrations.CreateShoppingChecks do
  use Ecto.Migration

  def change do
    # A row means "bought": the shopping list itself is worked out from the meal's dishes.
    create table(:shopping_checks) do
      add :meal_id, references(:meals, on_delete: :delete_all), null: false
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:shopping_checks, [:meal_id, :ingredient_id])
  end
end
