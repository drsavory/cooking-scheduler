defmodule CookingScheduler.Repo.Migrations.AddPreheatMinutesToAppliances do
  use Ecto.Migration

  # How long an oven takes to come up to temperature (ADR 0019).
  def change do
    alter table(:appliances) do
      add :preheat_minutes, :integer, null: false, default: 15
    end
  end
end
