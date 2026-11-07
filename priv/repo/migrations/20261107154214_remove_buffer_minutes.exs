defmodule CookingScheduler.Repo.Migrations.RemoveBufferMinutes do
  use Ecto.Migration

  # Buffer time is gone: any buffer a dish had is folded into its cook time so planned
  # schedules don't move.
  def up do
    for table <- [:dishes, :meal_dishes] do
      execute "UPDATE #{table} SET cook_minutes = cook_minutes + buffer_minutes"

      alter table(table) do
        remove :buffer_minutes
      end
    end
  end

  def down do
    for table <- [:dishes, :meal_dishes] do
      alter table(table) do
        add :buffer_minutes, :integer, null: false, default: 0
      end
    end
  end
end
