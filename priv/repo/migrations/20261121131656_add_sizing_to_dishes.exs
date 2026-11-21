defmodule CookingScheduler.Repo.Migrations.AddSizingToDishes do
  use Ecto.Migration

  # Sized dishes (ADR 0029): a cook time worked out from weight, e.g. a turkey at
  # 40 minutes per kg plus 20. Meal dishes copy the rule and keep their own weight.
  def change do
    alter table(:dishes) do
      add :size_unit, :string
      add :minutes_per_size, :integer
      add :base_minutes, :integer, null: false, default: 0
    end

    alter table(:meal_dishes) do
      add :size_unit, :string
      add :minutes_per_size, :integer
      add :base_minutes, :integer, null: false, default: 0
      add :size, :float
    end
  end
end
