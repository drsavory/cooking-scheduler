defmodule CookingScheduler.Repo.Migrations.HobsToRings do
  use Ecto.Migration

  def up do
    alter table(:appliances) do
      add :size, :string
    end

    # Any existing hob becomes that many individual medium rings.
    execute """
    INSERT INTO appliances (kind, name, size, inserted_at, updated_at)
    SELECT 'ring', 'Medium ring', 'medium', now(), now()
    FROM appliances a, generate_series(1, a.burners) g
    WHERE a.kind = 'hob'
    """

    execute "DELETE FROM appliances WHERE kind = 'hob'"

    alter table(:appliances) do
      remove :burners
    end
  end

  def down do
    alter table(:appliances) do
      add :burners, :integer
    end

    execute "DELETE FROM appliances WHERE kind = 'ring'"

    alter table(:appliances) do
      remove :size
    end
  end
end
