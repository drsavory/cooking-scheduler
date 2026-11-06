defmodule CookingScheduler.Kitchen do
  @moduledoc "The user's kitchen: ovens, hobs and other appliances."

  import Ecto.Query
  alias CookingScheduler.Repo
  alias CookingScheduler.Kitchen.Appliance

  def list_appliances do
    Repo.all(from a in Appliance, order_by: [asc: a.kind, asc: a.id])
  end

  def get_appliance!(id), do: Repo.get!(Appliance, id)

  def change_appliance(%Appliance{} = appliance, attrs \\ %{}) do
    Appliance.changeset(appliance, attrs)
  end

  def create_appliance(attrs) do
    %Appliance{} |> Appliance.changeset(attrs) |> Repo.insert()
  end

  def update_appliance(%Appliance{} = appliance, attrs) do
    appliance |> Appliance.changeset(attrs) |> Repo.update()
  end

  @doc "Adds an oven in the given scale with a sensible default range, ready to tweak in place."
  def add_oven(unit \\ :celsius) do
    n = Repo.aggregate(from(a in Appliance, where: a.kind == :oven), :count)
    {min, max} = Appliance.default_range(unit)

    create_appliance(%{
      kind: :oven,
      name: if(n == 0, do: "Oven", else: "Oven #{n + 1}"),
      temp_unit: unit,
      min_temp: min,
      max_temp: max
    })
  end

  def add_other(name), do: create_appliance(%{kind: :other, name: name})

  def delete_appliance(%Appliance{} = appliance), do: Repo.delete(appliance)

  @doc "Number of individual hob rings of each size, e.g. `%{small: 2, medium: 4, large: 2}`."
  def ring_counts do
    counts =
      Repo.all(
        from a in Appliance,
          where: a.kind == :ring,
          group_by: a.size,
          select: {a.size, count(a.id)}
      )
      |> Map.new()

    Map.new(Appliance.ring_sizes(), &{&1, Map.get(counts, &1, 0)})
  end

  @doc """
  Adds (`1`) or removes (`-1`) one ring of the given size. Every ring is its
  own record so it can be assigned to a dish independently.
  """
  def adjust_rings(size, delta) when delta in [1, -1] do
    size = Appliance.ring_sizes() |> Enum.find(&(&1 == size)) || raise ArgumentError, "bad size"

    Repo.transaction(fn ->
      if delta == 1 do
        {:ok, _} = create_appliance(%{kind: :ring, size: size})
      else
        last =
          Repo.one(
            from a in Appliance,
              where: a.kind == :ring and a.size == ^size,
              order_by: [desc: a.id],
              limit: 1
          )

        if last, do: Repo.delete!(last)
      end

      renumber_rings(size)
    end)
  end

  defp renumber_rings(size) do
    rings =
      Repo.all(from a in Appliance, where: a.kind == :ring and a.size == ^size, order_by: a.id)

    base = Appliance.ring_name(size)

    rings
    |> Enum.with_index(1)
    |> Enum.each(fn {ring, i} ->
      name = if length(rings) == 1, do: base, else: "#{base} #{i}"
      if ring.name != name, do: Repo.update!(Ecto.Changeset.change(ring, name: name))
    end)
  end
end
