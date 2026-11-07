defmodule CookingScheduler.Repo.Migrations.AddOvenShareToDishes do
  use Ecto.Migration

  def change do
    alter table(:dishes) do
      add :oven_share, :string, null: false, default: "third"
    end

    alter table(:saved_dishes) do
      add :oven_share, :string, null: false, default: "third"
    end
  end
end
