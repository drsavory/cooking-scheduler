# Seeds a kitchen and one meal so a fresh database has something to look at:
#
#   * The kitchen as set up in the dev database (November 2026): two gas-mark ovens, seven
#     hob rings, a slow cooker, a microwave and a grill.
#   * "Christmas 2025", taken from the 2025 tab of the "Christmas Food Cooking Times"
#     spreadsheet via `CookingScheduler.Meals.Starter`, with each oven dish pinned to the oven
#     the sheet put it in. Creating the dishes also fills the dish library, which then gets
#     tagged.
#
# Safe to run more than once: each section is skipped when its data is already there.
#
#     mix run priv/repo/seeds.exs

import Ecto.Query

alias CookingScheduler.{Kitchen, Meals, Repo}
alias CookingScheduler.Meals.{Meal, Starter}

# ---- Kitchen ---------------------------------------------------------------------

if Kitchen.list_appliances() == [] do
  for name <- ["Left Oven", "Right Oven"] do
    {:ok, _} =
      Kitchen.create_appliance(%{
        kind: :oven,
        name: name,
        temp_unit: :gas_mark,
        min_temp: 0.25,
        max_temp: 9.0
      })
  end

  # Rings are added one at a time so Kitchen names them ("Medium ring 1" ...).
  for {size, count} <- [small: 1, medium: 4, large: 2], _ <- 1..count do
    {:ok, _} = Kitchen.adjust_rings(size, 1)
  end

  for name <- ["Slow cooker", "Microwave", "Grill"] do
    {:ok, _} = Kitchen.add_other(name)
  end

  IO.puts("Seeded the kitchen")
else
  IO.puts("Kitchen already set up, leaving it alone")
end

# ---- Christmas 2025 --------------------------------------------------------------

meal_name = "Christmas 2025"

# The sheet's "Oven" column: 1 is the left oven, 2 the right.
oven_for = %{
  "Turkey (6.1 kg)" => "Right Oven",
  "Roast potatoes" => "Right Oven",
  "Pigs in blankets" => "Right Oven",
  "Fig and almond stuffing" => "Right Oven",
  "Chestnut and bacon cake" => "Left Oven",
  "Roast veg" => "Left Oven",
  "Salmon" => "Left Oven",
  "Yorkshire puddings" => "Left Oven"
}

# Labels for the library copies of the dishes.
tags_for = %{
  "Turkey (6.1 kg)" => ~w(main protein),
  "Salmon" => ~w(main protein),
  "Pigs in blankets" => ~w(side protein),
  "Roast potatoes" => ~w(carbs side),
  "Grilled potato" => ~w(carbs side),
  "Yorkshire puddings" => ~w(side),
  "Fig and almond stuffing" => ~w(side),
  "Chestnut and bacon cake" => ~w(side),
  "Roast veg" => ~w(veg side),
  "Steamed veg" => ~w(veg side),
  "Red cabbage and apple" => ~w(veg side),
  "Umami sprouts (after hob)" => ~w(veg side),
  "Umami sweet spicy sprouts" => ~w(veg side),
  "Gravy" => ~w(sauce)
}

if Repo.exists?(from m in Meal, where: m.name == ^meal_name) do
  IO.puts("#{meal_name} already exists, leaving it alone")
else
  kitchen = Kitchen.list_appliances()

  appliance_named = fn name ->
    case Enum.find(kitchen, &(String.downcase(&1.name) == String.downcase(name))) do
      nil -> nil
      appliance -> appliance.id
    end
  end

  {:ok, meal} =
    Meals.create_meal(%{name: meal_name, date: ~D[2025-12-25], serve_at: ~T[13:30:00]})

  Repo.transaction(fn ->
    for {attrs, hint} <- Starter.dishes() do
      appliance_id =
        case {hint, Map.get(oven_for, attrs.name)} do
          {nil, nil} -> nil
          {nil, oven} -> appliance_named.(oven)
          {hint, _} -> appliance_named.(hint)
        end

      {:ok, _} = Meals.create_meal_dish(meal, Map.put(attrs, :appliance_id, appliance_id))
    end

    for dish <- Meals.list_dishes(), tags = Map.get(tags_for, dish.name), tags != nil do
      {:ok, _} = Meals.update_dish(dish, %{tags: tags})
    end
  end)

  IO.puts("Seeded #{meal_name} with #{length(Starter.dishes())} dishes")
end
