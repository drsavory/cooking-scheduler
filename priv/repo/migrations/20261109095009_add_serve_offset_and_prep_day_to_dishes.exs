defmodule CookingScheduler.Repo.Migrations.AddServeOffsetAndPrepDayToDishes do
  use Ecto.Migration

  # Courses (ADR 0018): a dish can be served before or after the main serving time.
  # Prep timing (ADR 0022): when the prep for a dish is meant to happen.
  def change do
    for table <- [:dishes, :meal_dishes] do
      alter table(table) do
        add :serve_offset_minutes, :integer, null: false, default: 0
        add :prep_day, :string, null: false, default: "before_cooking"
      end
    end
  end
end
