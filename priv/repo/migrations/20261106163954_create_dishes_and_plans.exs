defmodule CookingScheduler.Repo.Migrations.CreateDishesAndPlans do
  use Ecto.Migration

  def change do
    # A single row holding the meal-wide settings (just the serving time for now).
    create table(:plans) do
      add :serve_at, :time, null: false
      timestamps(type: :utc_datetime)
    end

    create table(:dishes) do
      add :name, :string, null: false
      add :method, :string, null: false
      add :prep_minutes, :integer, null: false, default: 0
      add :cook_minutes, :integer, null: false, default: 0
      # extra safety margin added to the cooking time when scheduling
      add :buffer_minutes, :integer, null: false, default: 0
      add :rest_minutes, :integer, null: false, default: 0
      # oven dishes
      add :temp, :float
      add :temp_unit, :string
      # hob dishes
      add :ring_size, :string
      # pinned oven (oven dishes) or appliance (slow cooker, grill...); null = let the app choose
      add :appliance_id, references(:appliances, on_delete: :nilify_all)
      add :notes, :text
      add :link, :string
      add :ingredients_in, :boolean, null: false, default: false
      add :prepped, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create index(:dishes, [:appliance_id])
  end
end
