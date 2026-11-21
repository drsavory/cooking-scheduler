defmodule CookingScheduler.Repo.Migrations.AddDoneTempToDishes do
  use Ecto.Migration

  # Done when the inside reaches this temperature, e.g. a turkey at 74°C (ADR 0029).
  def change do
    for t <- [:dishes, :meal_dishes] do
      alter table(t) do
        add :done_temp, :float
        add :done_temp_unit, :string
      end
    end
  end
end
