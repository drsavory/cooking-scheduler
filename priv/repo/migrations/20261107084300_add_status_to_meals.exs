defmodule CookingScheduler.Repo.Migrations.AddStatusToMeals do
  use Ecto.Migration

  def up do
    alter table(:meals) do
      add :status, :string, null: false, default: "planning"
    end

    # Backfill from existing progress: finished or fully-done meals are complete, any started
    # dish means cooking, everything else stays in planning.
    execute """
    UPDATE meals SET status = 'complete' WHERE finished_at IS NOT NULL
    """

    execute """
    UPDATE meals SET status = 'cooking'
    WHERE status = 'planning' AND EXISTS (
      SELECT 1 FROM dishes d WHERE d.meal_id = meals.id
        AND (d.cook_started_at IS NOT NULL OR d.cook_done_at IS NOT NULL))
    """

    execute """
    UPDATE meals SET status = 'complete'
    WHERE status = 'cooking' AND NOT EXISTS (
      SELECT 1 FROM dishes d WHERE d.meal_id = meals.id
        AND d.cook_minutes + d.buffer_minutes > 0 AND d.cook_done_at IS NULL)
    """
  end

  def down do
    alter table(:meals) do
      remove :status
    end
  end
end
