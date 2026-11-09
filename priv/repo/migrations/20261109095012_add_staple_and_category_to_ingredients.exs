defmodule CookingScheduler.Repo.Migrations.AddStapleAndCategoryToIngredients do
  use Ecto.Migration

  # Shopping list groups (ADR 0021): cupboard staples and aisle categories.
  def change do
    alter table(:ingredients) do
      add :staple, :boolean, null: false, default: false
      add :category, :string
    end
  end
end
