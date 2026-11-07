defmodule CookingScheduler.Meals do
  @moduledoc """
  Meals (e.g. "Christmas 2025"), the dishes in each one, and the reusable library of
  saved dishes they're copied from.
  """

  import Ecto.Query
  alias CookingScheduler.Repo
  alias CookingScheduler.Meals.{Dish, Meal, SavedDish, Starter}

  @default_serve ~T[13:30:00]

  # ---- meals ----------------------------------------------------------------

  @doc "All meals, most recent first."
  def list_meals, do: Repo.all(from m in Meal, order_by: [desc: m.date, desc: m.id])

  def get_meal!(id), do: Repo.get!(Meal, id)

  @doc """
  Every meal, most recent first, with what the home page shows about each:
  `%{meal:, dishes:, prep_minutes:, status:, delay:}`.

  `status` is `:planned` (nothing started), `:cooking`, or `:cooked` (every timed dish is
  done, or the meal was finished early with `finish_meal/1`). `delay` is how many minutes after the serving time dinner was actually ready (0 if on
  time), and nil until the meal is cooked.
  """
  def list_meal_summaries do
    dishes = Repo.all(from(d in Dish)) |> Enum.group_by(& &1.meal_id)

    for meal <- list_meals() do
      summarize(meal, Map.get(dishes, meal.id, []))
    end
  end

  def summarize(%Meal{} = meal, dishes) do
    timed = Enum.filter(dishes, &(&1.cook_minutes + &1.buffer_minutes > 0))
    started = Enum.filter(timed, &(&1.cook_started_at || &1.cook_done_at))

    status =
      cond do
        started == [] -> :planned
        meal.finished_at || Enum.all?(timed, & &1.cook_done_at) -> :cooked
        true -> :cooking
      end

    # Dishes skipped when a meal is finished early don't count towards the delay.
    delay =
      if status == :cooked do
        ready =
          for d <- timed, d.cook_done_at, do: d.cook_done_at + d.rest_minutes

        max(Enum.max(ready, fn -> 0 end) - Meal.serve_minutes(meal), 0)
      end

    %{
      meal: meal,
      dishes: length(dishes),
      prep_minutes: dishes |> Enum.map(& &1.prep_minutes) |> Enum.sum(),
      status: status,
      delay: delay
    }
  end

  def change_meal(%Meal{} = meal, attrs \\ %{}), do: Meal.changeset(meal, attrs)
  def update_meal(%Meal{} = meal, attrs), do: meal |> Meal.changeset(attrs) |> Repo.update()
  def delete_meal(%Meal{} = meal), do: Repo.delete(meal)

  @doc "Creates a blank meal dated today."
  def create_meal(attrs \\ %{}) do
    %Meal{name: "New meal", date: Date.utc_today(), serve_at: @default_serve}
    |> Meal.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new meal containing a copy of every dish from `source` (see `copy_dishes/2`).
  """
  def create_meal_from(%Meal{} = source, attrs \\ %{}) do
    Repo.transaction(fn ->
      {:ok, meal} =
        %Meal{name: next_name(source.name), date: Date.utc_today(), serve_at: source.serve_at}
        |> Meal.changeset(attrs)
        |> Repo.insert()

      copy_dishes(source, meal)

      meal
    end)
  end

  @copied ~w(name method ring_size temp temp_unit prep_minutes cook_minutes buffer_minutes
             rest_minutes appliance_id notes link saved_dish_id)a

  @doc """
  Copies every dish from `source` into `target`: same times, temperatures, notes and
  links, with the day's progress cleared and ingredients/prep unticked.
  """
  def copy_dishes(%Meal{} = source, %Meal{} = target) do
    for dish <- list_dishes(source) do
      fields = dish |> Map.take(@copied) |> Map.put(:meal_id, target.id)
      Repo.insert!(struct(Dish, fields))
    end

    :ok
  end

  # "Christmas 2025" -> "Christmas 2026"; anything else gets " (copy)".
  defp next_name(name) do
    case Regex.run(~r/^(.*?)(\d{4})$/, name) do
      [_, prefix, year] -> prefix <> Integer.to_string(String.to_integer(year) + 1)
      _ -> name <> " (copy)"
    end
  end

  @doc "Moves dinner to the given minutes after midnight."
  def set_serve_minutes(%Meal{} = meal, minutes) do
    minutes = minutes |> max(0) |> min(1439)
    update_meal(meal, %{serve_at: Time.new!(div(minutes, 60), rem(minutes, 60), 0)})
  end

  # ---- dishes in a meal -----------------------------------------------------

  def list_dishes(%Meal{id: id}),
    do: Repo.all(from d in Dish, where: d.meal_id == ^id, order_by: d.id)

  def get_dish!(id), do: Repo.get!(Dish, id)

  def change_dish(%Dish{} = dish, attrs \\ %{}), do: Dish.changeset(dish, attrs)

  def create_dish(%Meal{} = meal, attrs) do
    %Dish{meal_id: meal.id}
    |> Dish.changeset(attrs)
    |> Repo.insert()
    |> sync_after()
  end

  def update_dish(%Dish{} = dish, attrs) do
    dish |> Dish.changeset(attrs) |> Repo.update() |> sync_after()
  end

  def delete_dish(%Dish{} = dish), do: Repo.delete(dish)

  @doc "Adds a dish with sensible defaults for how it's cooked, ready to edit in place."
  def add_dish(%Meal{} = meal, :oven, kitchen) do
    unit = kitchen |> Enum.find(&(&1.kind == :oven)) |> then(&((&1 && &1.temp_unit) || :gas_mark))

    create_dish(meal, %{
      name: "New oven dish",
      method: :oven,
      temp_unit: unit,
      temp: default_temp(unit),
      cook_minutes: 60
    })
  end

  def add_dish(%Meal{} = meal, :ring, _kitchen),
    do:
      create_dish(meal, %{
        name: "New hob dish",
        method: :ring,
        ring_size: :medium,
        cook_minutes: 20
      })

  def add_dish(%Meal{} = meal, :appliance, _kitchen),
    do:
      create_dish(meal, %{
        name: "New slow cooker / grill dish",
        method: :appliance,
        cook_minutes: 60
      })

  defp default_temp(:celsius), do: 180
  defp default_temp(:fahrenheit), do: 350
  defp default_temp(:gas_mark), do: 4

  # ---- live cooking progress (times are minutes after midnight) --------------

  def set_prepped(%Dish{} = d, value),
    do: d |> Ecto.Changeset.change(prepped: value) |> Repo.update()

  def start_cooking(%Dish{} = d, at),
    do: d |> Ecto.Changeset.change(cook_started_at: at) |> Repo.update()

  def finish_cooking(%Dish{} = d, at),
    do: d |> Ecto.Changeset.change(cook_done_at: at) |> Repo.update()

  def undo_finish(%Dish{} = d), do: d |> Ecto.Changeset.change(cook_done_at: nil) |> Repo.update()

  def undo_start(%Dish{} = d),
    do: d |> Ecto.Changeset.change(cook_started_at: nil, cook_done_at: nil) |> Repo.update()

  def add_extra(%Dish{} = d, minutes),
    do:
      d
      |> Ecto.Changeset.change(extra_minutes: max(d.extra_minutes + minutes, 0))
      |> Repo.update()

  @doc "Ends the meal now, even if some dishes weren't cooked. Undo with `reset_cooking/1`."
  def finish_meal(%Meal{} = meal) do
    meal
    |> Ecto.Changeset.change(finished_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  @doc """
  Clears started/finished/extra-time on a meal's dishes and its finished mark (keeps the
  plan and prepped ticks), taking it back to "planned".
  """
  def reset_cooking(%Meal{id: id}) do
    Repo.update_all(from(d in Dish, where: d.meal_id == ^id),
      set: [cook_started_at: nil, cook_done_at: nil, extra_minutes: 0]
    )

    Repo.update_all(from(m in Meal, where: m.id == ^id), set: [finished_at: nil])

    :ok
  end

  # ---- starter menu ---------------------------------------------------------

  @doc """
  Fills an empty meal with last year's menu (turkey, roasties, ...) so there's
  something to edit rather than a blank page. Does nothing if the meal has dishes.
  """
  def load_starter_dishes(%Meal{} = meal, kitchen) do
    if list_dishes(meal) == [] do
      Repo.transaction(fn ->
        for {attrs, hint} <- Starter.dishes() do
          {:ok, _} =
            create_dish(meal, Map.put(attrs, :appliance_id, appliance_id_matching(kitchen, hint)))
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
      nil -> nil
      appliance -> appliance.id
    end
  end

  # ---- library of saved dishes ----------------------------------------------

  def list_saved_dishes, do: Repo.all(from s in SavedDish, order_by: fragment("lower(?)", s.name))
  def get_saved_dish!(id), do: Repo.get!(SavedDish, id)
  def change_saved_dish(%SavedDish{} = saved, attrs \\ %{}), do: SavedDish.changeset(saved, attrs)

  def create_saved_dish(attrs), do: %SavedDish{} |> SavedDish.changeset(attrs) |> Repo.insert()

  def update_saved_dish(%SavedDish{} = saved, attrs),
    do: saved |> SavedDish.changeset(attrs) |> Repo.update()

  def delete_saved_dish(%SavedDish{} = saved), do: Repo.delete(saved)

  @doc "Saved dishes that aren't already in `meal`."
  def saved_dishes_not_in(%Meal{id: id}) do
    in_meal =
      from d in Dish,
        where: d.meal_id == ^id and not is_nil(d.saved_dish_id),
        select: d.saved_dish_id

    Repo.all(
      from s in SavedDish,
        where: s.id not in subquery(in_meal),
        order_by: fragment("lower(?)", s.name)
    )
  end

  @doc "Adds a copy of a saved dish to a meal."
  def add_saved_dish(%Meal{} = meal, %SavedDish{} = saved) do
    attrs = Map.take(saved, SavedDish.template_fields())

    %Dish{meal_id: meal.id, saved_dish_id: saved.id}
    |> Dish.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Every meal each saved dish has been used in: `%{saved_dish_id => [{meal, dish}]}`, newest meal first."
  def usage_by_saved_dish do
    Repo.all(
      from d in Dish,
        join: m in assoc(d, :meal),
        where: not is_nil(d.saved_dish_id),
        order_by: [desc: m.date, desc: m.id],
        select: {d.saved_dish_id, m, d}
    )
    |> Enum.group_by(&elem(&1, 0), fn {_id, m, d} -> {m, d} end)
  end

  # Keeps the library current: when you edit a dish in a meal that hasn't been cooked yet,
  # the saved version takes on those values, so next time you start from how you did it
  # last. Placeholder names ("New oven dish") are never saved, and edits to meals that
  # have been started don't change the library.
  defp sync_after({:ok, %Dish{} = dish} = result) do
    if library_worthy?(dish) and not started?(dish.meal_id), do: sync_to_library(dish)
    result
  end

  defp sync_after(error), do: error

  defp started?(meal_id) do
    Repo.exists?(
      from d in Dish,
        where:
          d.meal_id == ^meal_id and (not is_nil(d.cook_started_at) or not is_nil(d.cook_done_at))
    )
  end

  defp library_worthy?(%Dish{name: name}), do: not String.starts_with?(name, "New ")

  defp sync_to_library(%Dish{} = dish) do
    attrs = Map.take(dish, SavedDish.template_fields())
    key = String.downcase(dish.name)

    saved =
      case Repo.one(from s in SavedDish, where: fragment("lower(?)", s.name) == ^key) do
        nil -> %SavedDish{}
        existing -> existing
      end

    {:ok, saved} = saved |> SavedDish.changeset(attrs) |> Repo.insert_or_update()

    if dish.saved_dish_id != saved.id do
      dish |> Ecto.Changeset.change(saved_dish_id: saved.id) |> Repo.update!()
    end

    :ok
  end
end
