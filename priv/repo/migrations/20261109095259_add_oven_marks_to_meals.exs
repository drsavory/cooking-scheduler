defmodule CookingScheduler.Repo.Migrations.AddOvenMarksToMeals do
  use Ecto.Migration

  # Oven tasks ticked on the cook screen ("preheat:<oven id>:<dish id>"), see ADR 0019.
  def change do
    alter table(:meals) do
      add :oven_marks, {:array, :string}, null: false, default: []
    end
  end
end
