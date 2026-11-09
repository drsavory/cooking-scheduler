defmodule CookingScheduler.Repo.Migrations.AddNextTimeNotes do
  use Ecto.Migration

  # What to change next time, written after the meal (ADR 0024).
  def change do
    alter table(:meals) do
      add :next_time, :text
    end

    alter table(:meal_dishes) do
      add :next_time, :text
    end
  end
end
