defmodule CookingScheduler.Repo.Migrations.CreatePhotos do
  use Ecto.Migration

  def change do
    # A photo belongs to a meal or to one dish in a meal, never both. The file itself lives in
    # object storage under `key`.
    create table(:photos) do
      add :meal_id, references(:meals, on_delete: :delete_all)
      add :meal_dish_id, references(:meal_dishes, on_delete: :delete_all)
      add :key, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :integer, null: false
      add :filename, :string
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:photos, [:meal_id])
    create index(:photos, [:meal_dish_id])
    create unique_index(:photos, [:key])

    create constraint(:photos, :one_owner,
             check: "(meal_id IS NOT NULL) <> (meal_dish_id IS NOT NULL)"
           )
  end
end
