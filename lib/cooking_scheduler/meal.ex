defmodule CookingScheduler.Meal do
  @moduledoc "The meal being planned: the serving time and the list of dishes."

  import Ecto.Query
  alias CookingScheduler.Repo
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meal.{Dish, Plan, Starter}

  @default_serve ~T[13:30:00]

  def get_plan do
    Repo.one(from p in Plan, limit: 1) || Repo.insert!(%Plan{serve_at: @default_serve})
  end

  def update_plan_changeset(%Plan{} = plan, attrs \\ %{}), do: Plan.changeset(plan, attrs)

  def update_plan(%Plan{} = plan, attrs), do: plan |> Plan.changeset(attrs) |> Repo.update()

  def list_dishes, do: Repo.all(from d in Dish, order_by: d.id)
  def get_dish!(id), do: Repo.get!(Dish, id)

  def change_dish(%Dish{} = dish, attrs \\ %{}), do: Dish.changeset(dish, attrs)

  def create_dish(attrs), do: %Dish{} |> Dish.changeset(attrs) |> Repo.insert()
  def update_dish(%Dish{} = dish, attrs), do: dish |> Dish.changeset(attrs) |> Repo.update()
  def delete_dish(%Dish{} = dish), do: Repo.delete(dish)

  @doc "Adds a dish with sensible defaults for how it's cooked, ready to edit in place."
  def add_dish(:oven, kitchen) do
    unit = kitchen |> Enum.find(&(&1.kind == :oven)) |> then(&((&1 && &1.temp_unit) || :gas_mark))

    create_dish(%{
      name: "New oven dish",
      method: :oven,
      temp_unit: unit,
      temp: default_temp(unit),
      cook_minutes: 60
    })
  end

  def add_dish(:ring, _kitchen),
    do: create_dish(%{name: "New hob dish", method: :ring, ring_size: :medium, cook_minutes: 20})

  def add_dish(:appliance, _kitchen),
    do: create_dish(%{name: "New slow cooker / grill dish", method: :appliance, cook_minutes: 60})

  defp default_temp(:celsius), do: 180
  defp default_temp(:fahrenheit), do: 350
  defp default_temp(:gas_mark), do: 4

  @doc """
  Fills an empty meal with last year's menu (turkey, roasties, ...) so there's
  something to edit rather than a blank page. Does nothing if dishes already exist.
  """
  def load_starter_dishes(kitchen) do
    if list_dishes() == [] do
      Repo.transaction(fn ->
        for {attrs, hint} <- Starter.dishes() do
          {:ok, _} =
            create_dish(Map.put(attrs, :appliance_id, appliance_id_matching(kitchen, hint)))
        end
      end)
    else
      {:error, :not_empty}
    end
  end

  defp appliance_id_matching(_kitchen, nil), do: nil

  defp appliance_id_matching(kitchen, hint) do
    hint = String.downcase(hint)

    kitchen
    |> Enum.find(&(&1.kind == :other and String.contains?(String.downcase(&1.name), hint)))
    |> case do
      %Appliance{id: id} -> id
      nil -> nil
    end
  end
end
