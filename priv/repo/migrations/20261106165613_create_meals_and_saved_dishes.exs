defmodule CookingScheduler.Repo.Migrations.CreateMealsAndSavedDishes do
  use Ecto.Migration

  def up do
    create table(:meals) do
      add :name, :string, null: false
      add :date, :date, null: false
      add :serve_at, :time, null: false
      timestamps(type: :utc_datetime)
    end

    # The reusable library of dishes: a template each meal's dish is copied from.
    create table(:saved_dishes) do
      add :name, :string, null: false
      add :method, :string, null: false
      add :ring_size, :string
      add :temp, :float
      add :temp_unit, :string
      add :prep_minutes, :integer, null: false, default: 0
      add :cook_minutes, :integer, null: false, default: 0
      add :buffer_minutes, :integer, null: false, default: 0
      add :rest_minutes, :integer, null: false, default: 0
      add :notes, :text
      add :link, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:saved_dishes, ["lower(name)"], name: :saved_dishes_lower_name_index)

    alter table(:dishes) do
      add :meal_id, references(:meals, on_delete: :delete_all)
      add :saved_dish_id, references(:saved_dishes, on_delete: :nilify_all)
    end

    # The single "plan" becomes the first meal, and existing dishes belong to it.
    execute """
    INSERT INTO meals (name, date, serve_at, inserted_at, updated_at)
    SELECT 'Christmas dinner', inserted_at::date, serve_at, now(), now()
    FROM plans ORDER BY id LIMIT 1
    """

    execute """
    INSERT INTO meals (name, date, serve_at, inserted_at, updated_at)
    SELECT 'Christmas dinner', current_date, '13:30', now(), now()
    WHERE NOT EXISTS (SELECT 1 FROM meals) AND EXISTS (SELECT 1 FROM dishes)
    """

    execute "UPDATE dishes SET meal_id = (SELECT id FROM meals ORDER BY id LIMIT 1)"

    # Seed the library from existing dishes (latest version of each name).
    execute """
    INSERT INTO saved_dishes
      (name, method, ring_size, temp, temp_unit, prep_minutes, cook_minutes, buffer_minutes,
       rest_minutes, notes, link, inserted_at, updated_at)
    SELECT DISTINCT ON (lower(name))
      name, method, ring_size, temp, temp_unit, prep_minutes, cook_minutes, buffer_minutes,
      rest_minutes, notes, link, now(), now()
    FROM dishes
    WHERE name NOT LIKE 'New %'
    ORDER BY lower(name), id DESC
    """

    execute """
    UPDATE dishes d SET saved_dish_id = s.id
    FROM saved_dishes s WHERE lower(d.name) = lower(s.name)
    """

    execute "ALTER TABLE dishes ALTER COLUMN meal_id SET NOT NULL"
    create index(:dishes, [:meal_id])
    create index(:dishes, [:saved_dish_id])

    drop table(:plans)
  end

  def down do
    raise Ecto.MigrationError, "irreversible: meals replace the single plan"
  end
end
