defmodule CookingScheduler.Repo.Migrations.CreateAppliances do
  use Ecto.Migration

  def change do
    create table(:appliances) do
      add :kind, :string, null: false
      add :name, :string, null: false
      # ovens
      add :temp_unit, :string
      add :min_temp, :float
      add :max_temp, :float
      # hobs
      add :burners, :integer
      # anything else (slow cooker, air fryer, ...)
      add :notes, :string

      timestamps(type: :utc_datetime)
    end
  end
end
