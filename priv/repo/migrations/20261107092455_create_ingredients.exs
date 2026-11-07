defmodule CookingScheduler.Repo.Migrations.CreateIngredients do
  use Ecto.Migration

  def change do
    # One shared list of ingredients ("butter"), reused across many dishes.
    create table(:ingredients) do
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:ingredients, ["lower(name)"], name: :ingredients_lower_name_index)

    # An ingredient in one dish, with how much of it. Belongs to either a meal's dish or a
    # library (saved) dish, never both.
    create table(:dish_ingredients) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :dish_id, references(:dishes, on_delete: :delete_all)
      add :saved_dish_id, references(:saved_dishes, on_delete: :delete_all)
      add :quantity, :string
      timestamps(type: :utc_datetime)
    end

    create constraint(:dish_ingredients, :exactly_one_owner,
             check: "(dish_id IS NULL) <> (saved_dish_id IS NULL)"
           )

    create unique_index(:dish_ingredients, [:dish_id, :ingredient_id],
             where: "dish_id IS NOT NULL"
           )

    create unique_index(:dish_ingredients, [:saved_dish_id, :ingredient_id],
             where: "saved_dish_id IS NOT NULL"
           )

    create index(:dish_ingredients, [:ingredient_id])
  end
end
