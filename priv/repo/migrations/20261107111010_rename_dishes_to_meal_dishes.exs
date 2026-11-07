defmodule CookingScheduler.Repo.Migrations.RenameDishesToMealDishes do
  use Ecto.Migration

  # `dishes` (a dish in one meal) becomes `meal_dishes`, and the library `saved_dishes`
  # becomes `dishes`: the things you choose from.
  def up do
    rename table(:dishes), to: table(:meal_dishes)
    rename table(:meal_dishes), :saved_dish_id, to: :dish_id

    rename table(:dish_ingredients), :dish_id, to: :meal_dish_id
    rename table(:dish_ingredients), :saved_dish_id, to: :dish_id

    rename table(:saved_dishes), to: table(:dishes)

    execute "ALTER INDEX dishes_pkey RENAME TO meal_dishes_pkey"
    execute "ALTER INDEX saved_dishes_pkey RENAME TO dishes_pkey"
    execute "ALTER INDEX saved_dishes_lower_name_index RENAME TO dishes_lower_name_index"
  end

  def down do
    execute "ALTER INDEX dishes_lower_name_index RENAME TO saved_dishes_lower_name_index"
    execute "ALTER INDEX dishes_pkey RENAME TO saved_dishes_pkey"
    execute "ALTER INDEX meal_dishes_pkey RENAME TO dishes_pkey"

    rename table(:dishes), to: table(:saved_dishes)

    rename table(:dish_ingredients), :dish_id, to: :saved_dish_id
    rename table(:dish_ingredients), :meal_dish_id, to: :dish_id

    rename table(:meal_dishes), :dish_id, to: :saved_dish_id
    rename table(:meal_dishes), to: table(:dishes)
  end
end
