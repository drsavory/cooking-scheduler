defmodule CookingScheduler.Repo.Migrations.AddTagsToSavedDishes do
  use Ecto.Migration

  def change do
    alter table(:saved_dishes) do
      add :tags, {:array, :string}, null: false, default: []
    end
  end
end
