defmodule CookingScheduler.Repo.Migrations.AddCookingProgressToDishes do
  use Ecto.Migration

  def change do
    alter table(:dishes) do
      # Live progress on the day. Times are minutes after midnight.
      add :cook_started_at, :integer
      add :cook_done_at, :integer
      # extra cooking time added on the day ("needs another 10 minutes")
      add :extra_minutes, :integer, null: false, default: 0
    end
  end
end
