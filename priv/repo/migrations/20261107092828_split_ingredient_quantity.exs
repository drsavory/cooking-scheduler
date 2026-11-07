defmodule CookingScheduler.Repo.Migrations.SplitIngredientQuantity do
  use Ecto.Migration

  def up do
    alter table(:dish_ingredients) do
      add :amount, :float
      add :unit, :string
      remove :quantity
    end
  end

  def down do
    alter table(:dish_ingredients) do
      add :quantity, :string
      remove :amount
      remove :unit
    end
  end
end
