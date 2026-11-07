defmodule CookingScheduler.Repo.Migrations.AddFinishedAtToMeals do
  use Ecto.Migration

  def change do
    alter table(:meals) do
      # Set when the cook ends the meal early; a meal is also cooked once every timed dish is done.
      add :finished_at, :utc_datetime
    end
  end
end
