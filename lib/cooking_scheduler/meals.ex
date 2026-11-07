defmodule CookingScheduler.Meals do
  @moduledoc """
  Meals (e.g. "Christmas 2025"), the dishes in each one, and the dishes you can choose from  dishes they're copied from.
  """

  import Ecto.Query
  alias CookingScheduler.{Photos, Repo}

  alias CookingScheduler.Meals.{
    MealDish,
    DishIngredient,
    Ingredient,
    Meal,
    Dish,
    ShoppingCheck,
    Starter
  }

  @default_serve ~T[13:30:00]

  # ---- meals ----------------------------------------------------------------

  @doc "All meals, most recent first."
  def list_meals, do: Repo.all(from m in Meal, order_by: [desc: m.date, desc: m.id])

  def get_meal!(id), do: Repo.get!(Meal, id)

  @doc """
  Every meal, most recent first, with what the home page shows about each:
  `%{meal:, dishes:, prep_minutes:, status:, delay:}`.

  `status` is the meal's stored status: `:planning`, `:prepping` (planned, getting ingredients
  in), `:cooking` or `:complete` (every timed dish is done, or the meal was finished early with
  `finish_meal/1`). `delay` is how many minutes after the serving time dinner was actually
  ready (0 if on time), and nil until the meal is complete.
  """
  def list_meal_summaries do
    dishes = Repo.all(from(d in MealDish)) |> Enum.group_by(& &1.meal_id)

    for meal <- list_meals() do
      summarize(meal, Map.get(dishes, meal.id, []))
    end
  end

  def summarize(%Meal{} = meal, dishes) do
    timed = Enum.filter(dishes, &(&1.cook_minutes + &1.buffer_minutes > 0))
    # Dishes skipped when a meal is finished early don't count towards the delay.
    delay =
      if meal.status == :complete do
        ready =
          for d <- timed, d.cook_done_at, do: d.cook_done_at + d.rest_minutes

        max(Enum.max(ready, fn -> 0 end) - Meal.serve_minutes(meal), 0)
      end

    %{
      meal: meal,
      dishes: length(dishes),
      prep_minutes: dishes |> Enum.map(& &1.prep_minutes) |> Enum.sum(),
      status: meal.status,
      delay: delay
    }
  end

  def change_meal(%Meal{} = meal, attrs \\ %{}), do: Meal.changeset(meal, attrs)
  def update_meal(%Meal{} = meal, attrs), do: meal |> Meal.changeset(attrs) |> Repo.update()

  def delete_meal(%Meal{} = meal) do
    keys = Photos.keys_for_meal(meal)
    result = Repo.delete(meal)
    with {:ok, _} <- result, do: Photos.purge(keys)
    result
  end

  @doc "Creates a blank meal dated today."
  def create_meal(attrs \\ %{}) do
    %Meal{name: "New meal", date: Date.utc_today(), serve_at: @default_serve}
    |> Meal.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new meal containing a copy of every dish from `source` (see `copy_meal_dishes/2`).
  """
  def create_meal_from(%Meal{} = source, attrs \\ %{}) do
    Repo.transaction(fn ->
      {:ok, meal} =
        %Meal{name: next_name(source.name), date: Date.utc_today(), serve_at: source.serve_at}
        |> Meal.changeset(attrs)
        |> Repo.insert()

      copy_meal_dishes(source, meal)

      meal
    end)
  end

  @copied ~w(name method ring_size oven_share temp temp_unit prep_minutes cook_minutes buffer_minutes
             rest_minutes appliance_id notes link dish_id)a

  @doc """
  Copies every dish from `source` into `target`: same times, temperatures, notes and
  links, with the day's progress cleared and ingredients/prep unticked.
  """
  def copy_meal_dishes(%Meal{} = source, %Meal{} = target) do
    for dish <- list_meal_dishes(source) do
      fields = dish |> Map.take(@copied) |> Map.put(:meal_id, target.id)
      copy = Repo.insert!(struct(MealDish, fields))
      copy_ingredients({:meal_dish, dish.id}, {:meal_dish, copy.id})
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

  def list_meal_dishes(%Meal{id: id}),
    do: Repo.all(from d in MealDish, where: d.meal_id == ^id, order_by: d.id)

  def get_meal_dish!(id), do: Repo.get!(MealDish, id)

  def change_meal_dish(%MealDish{} = dish, attrs \\ %{}), do: MealDish.changeset(dish, attrs)

  def create_meal_dish(%Meal{} = meal, attrs) do
    %MealDish{meal_id: meal.id}
    |> MealDish.changeset(attrs)
    |> Repo.insert()
    |> sync_after()
  end

  def update_meal_dish(%MealDish{} = dish, attrs) do
    dish |> MealDish.changeset(attrs) |> Repo.update() |> sync_after()
  end

  def delete_meal_dish(%MealDish{} = dish) do
    keys = Photos.keys_for_meal_dish(dish)
    result = Repo.delete(dish)
    with {:ok, _} <- result, do: Photos.purge(keys)
    result
  end

  @doc "Adds a dish with sensible defaults for how it's cooked, ready to edit in place."
  def add_meal_dish(%Meal{} = meal, :oven, kitchen) do
    unit = kitchen |> Enum.find(&(&1.kind == :oven)) |> then(&((&1 && &1.temp_unit) || :gas_mark))

    create_meal_dish(meal, %{
      name: "New oven dish",
      method: :oven,
      temp_unit: unit,
      temp: default_temp(unit),
      cook_minutes: 60
    })
  end

  def add_meal_dish(%Meal{} = meal, :ring, _kitchen),
    do:
      create_meal_dish(meal, %{
        name: "New hob dish",
        method: :ring,
        ring_size: :medium,
        cook_minutes: 20
      })

  def add_meal_dish(%Meal{} = meal, :appliance, _kitchen),
    do:
      create_meal_dish(meal, %{
        name: "New slow cooker / grill dish",
        method: :appliance,
        cook_minutes: 60
      })

  defp default_temp(:celsius), do: 180
  defp default_temp(:fahrenheit), do: 350
  defp default_temp(:gas_mark), do: 4

  # ---- live cooking progress (times are minutes after midnight) --------------

  def set_prepped(%MealDish{} = d, value),
    do: d |> Ecto.Changeset.change(prepped: value) |> Repo.update()

  def set_ingredients_in(%MealDish{} = d, value),
    do: d |> Ecto.Changeset.change(ingredients_in: value) |> Repo.update()

  @doc "Ticks (or unticks) \"all ingredients in\" for every dish in a meal."
  def set_all_ingredients_in(%Meal{id: id}, value) do
    Repo.update_all(from(d in MealDish, where: d.meal_id == ^id), set: [ingredients_in: value])
    :ok
  end

  def start_cooking(%MealDish{} = d, at),
    do: d |> Ecto.Changeset.change(cook_started_at: at) |> update_progress()

  def finish_cooking(%MealDish{} = d, at),
    do: d |> Ecto.Changeset.change(cook_done_at: at) |> update_progress()

  def undo_finish(%MealDish{} = d),
    do: d |> Ecto.Changeset.change(cook_done_at: nil) |> update_progress()

  def undo_start(%MealDish{} = d),
    do: d |> Ecto.Changeset.change(cook_started_at: nil, cook_done_at: nil) |> update_progress()

  defp update_progress(changeset) do
    with {:ok, dish} <- Repo.update(changeset) do
      sync_status(dish.meal_id)
      {:ok, dish}
    end
  end

  @doc "Moves a planning meal on to prepping (or back again)."
  def set_prep_status(%Meal{status: status} = meal, new)
      when status in [:planning, :prepping] and new in [:planning, :prepping],
      do: meal |> Ecto.Changeset.change(status: new) |> Repo.update()

  # Keeps cooking/complete in step with dish progress. Planning/prepping are the cook's call,
  # so they're only touched when progress is undone (back to prepping).
  defp sync_status(meal_id) do
    meal = Repo.get!(Meal, meal_id)
    dishes = Repo.all(from d in MealDish, where: d.meal_id == ^meal_id)
    timed = Enum.filter(dishes, &(&1.cook_minutes + &1.buffer_minutes > 0))
    started? = Enum.any?(timed, &(&1.cook_started_at || &1.cook_done_at))

    new =
      cond do
        not started? and meal.status in [:cooking, :complete] -> :prepping
        not started? -> meal.status
        meal.finished_at || Enum.all?(timed, & &1.cook_done_at) -> :complete
        true -> :cooking
      end

    if new != meal.status, do: meal |> Ecto.Changeset.change(status: new) |> Repo.update()
    :ok
  end

  def add_extra(%MealDish{} = d, minutes),
    do:
      d
      |> Ecto.Changeset.change(extra_minutes: max(d.extra_minutes + minutes, 0))
      |> Repo.update()

  @doc "Ends the meal now, even if some dishes weren't cooked. Undo with `reset_cooking/1`."
  def finish_meal(%Meal{} = meal) do
    meal
    |> Ecto.Changeset.change(finished_at: DateTime.utc_now(:second), status: :complete)
    |> Repo.update()
  end

  @doc """
  Clears started/finished/extra-time on a meal's dishes and its finished mark (keeps the
  plan and prepped ticks), taking it back to "prepping".
  """
  def reset_cooking(%Meal{id: id}) do
    Repo.update_all(from(d in MealDish, where: d.meal_id == ^id),
      set: [cook_started_at: nil, cook_done_at: nil, extra_minutes: 0]
    )

    Repo.update_all(from(m in Meal, where: m.id == ^id),
      set: [finished_at: nil, status: :prepping]
    )

    :ok
  end

  # ---- starter menu ---------------------------------------------------------

  @doc """
  Fills an empty meal with last year's menu (turkey, roasties, ...) so there's
  something to edit rather than a blank page. Does nothing if the meal has dishes.
  """
  def load_starter_dishes(%Meal{} = meal, kitchen) do
    if list_meal_dishes(meal) == [] do
      Repo.transaction(fn ->
        for {attrs, hint} <- Starter.dishes() do
          {:ok, _} =
            create_meal_dish(
              meal,
              Map.put(attrs, :appliance_id, appliance_id_matching(kitchen, hint))
            )
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

  # ---- library of dishes ----------------------------------------------

  def list_dishes, do: Repo.all(from s in Dish, order_by: fragment("lower(?)", s.name))
  def get_dish!(id), do: Repo.get!(Dish, id)
  def change_dish(%Dish{} = dish, attrs \\ %{}), do: Dish.changeset(dish, attrs)

  def create_dish(attrs), do: %Dish{} |> Dish.changeset(attrs) |> Repo.insert()

  def update_dish(%Dish{} = dish, attrs),
    do: dish |> Dish.changeset(attrs) |> Repo.update()

  def delete_dish(%Dish{} = dish), do: Repo.delete(dish)

  @doc "Dishes that aren't already in `meal`."
  def dishes_not_in(%Meal{id: id}) do
    in_meal =
      from d in MealDish,
        where: d.meal_id == ^id and not is_nil(d.dish_id),
        select: d.dish_id

    Repo.all(
      from s in Dish,
        where: s.id not in subquery(in_meal),
        order_by: fragment("lower(?)", s.name)
    )
  end

  @doc "Adds a copy of a dish to a meal (a `MealDish`)."
  def add_dish_to_meal(%Meal{} = meal, %Dish{} = dish) do
    attrs = Map.take(dish, Dish.template_fields())

    with {:ok, meal_dish} <-
           %MealDish{meal_id: meal.id, dish_id: dish.id}
           |> MealDish.changeset(attrs)
           |> Repo.insert() do
      copy_ingredients({:dish, dish.id}, {:meal_dish, meal_dish.id})
      {:ok, meal_dish}
    end
  end

  @doc "Every meal each dish has been used in: `%{dish_id => [{meal, dish}]}`, newest meal first."
  def usage_by_dish do
    Repo.all(
      from d in MealDish,
        join: m in assoc(d, :meal),
        where: not is_nil(d.dish_id),
        order_by: [desc: m.date, desc: m.id],
        select: {d.dish_id, m, d}
    )
    |> Enum.group_by(&elem(&1, 0), fn {_id, m, d} -> {m, d} end)
  end

  # Keeps the library current: when you edit a dish in a meal that hasn't been cooked yet,
  # the library dish takes on those values, so next time you start from how you did it
  # last. Placeholder names ("New oven dish") are never saved, and edits to meals that
  # have been started don't change the library.
  defp sync_after({:ok, %MealDish{} = dish} = result) do
    if library_worthy?(dish) and not started?(dish.meal_id), do: sync_to_library(dish)
    result
  end

  defp sync_after(error), do: error

  defp started?(meal_id) do
    Repo.exists?(
      from d in MealDish,
        where:
          d.meal_id == ^meal_id and (not is_nil(d.cook_started_at) or not is_nil(d.cook_done_at))
    )
  end

  defp library_worthy?(%MealDish{name: name}), do: not String.starts_with?(name, "New ")

  defp sync_to_library(%MealDish{} = dish) do
    attrs = Map.take(dish, Dish.template_fields())
    key = String.downcase(dish.name)

    saved =
      case Repo.one(from s in Dish, where: fragment("lower(?)", s.name) == ^key) do
        nil -> %Dish{}
        existing -> existing
      end

    {:ok, saved} = saved |> Dish.changeset(attrs) |> Repo.insert_or_update()

    if dish.dish_id != saved.id do
      dish |> Ecto.Changeset.change(dish_id: saved.id) |> Repo.update!()
    end

    :ok
  end

  # ---- ingredients -------------------------------------------------------------

  @doc "Every known ingredient, A to Z."
  def list_ingredients, do: Repo.all(from i in Ingredient, order_by: fragment("lower(?)", i.name))

  @doc """
  Everything a meal needs, one row per ingredient, A to Z:
  `%{ingredient:, amounts:, dishes:, bought?:}`. `amounts` totals each unit separately (g with g, never
  g with kg) as `[{amount, unit}]`, and is empty when no dish gives an amount. `dishes` names
  the dishes that use it.
  """
  def shopping_list(%Meal{id: id}) do
    bought =
      MapSet.new(
        Repo.all(from c in ShoppingCheck, where: c.meal_id == ^id, select: c.ingredient_id)
      )

    Repo.all(
      from di in DishIngredient,
        join: d in assoc(di, :meal_dish),
        join: i in assoc(di, :ingredient),
        where: d.meal_id == ^id,
        order_by: [fragment("lower(?)", i.name), d.name],
        select: {i, di.amount, di.unit, d.name}
    )
    |> Enum.group_by(fn {i, _, _, _} -> i end)
    |> Enum.map(fn {ingredient, rows} ->
      amounts =
        rows
        |> Enum.filter(fn {_, amount, _, _} -> amount end)
        |> Enum.group_by(fn {_, _, unit, _} -> unit end, fn {_, amount, _, _} -> amount end)
        |> Enum.map(fn {unit, list} -> {Enum.sum(list), unit} end)
        |> Enum.sort_by(fn {_, unit} -> to_string(unit) end)

      dishes = rows |> Enum.map(fn {_, _, _, name} -> name end) |> Enum.uniq()

      %{
        ingredient: ingredient,
        amounts: amounts,
        dishes: dishes,
        bought?: MapSet.member?(bought, ingredient.id)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.ingredient.name))
  end

  @doc """
  Ticks an ingredient off a meal's shopping list, or puts it back. Dishes using it follow:
  a dish is "all ingredients in" once every one of its ingredients is bought, and not otherwise.
  """
  def set_bought(%Meal{id: id} = meal, ingredient_id, true) do
    Repo.insert!(%ShoppingCheck{meal_id: id, ingredient_id: ingredient_id},
      on_conflict: :nothing
    )

    sync_ingredients_in(meal, ingredient_id)
  end

  def set_bought(%Meal{id: id} = meal, ingredient_id, false) do
    Repo.delete_all(
      from c in ShoppingCheck, where: c.meal_id == ^id and c.ingredient_id == ^ingredient_id
    )

    sync_ingredients_in(meal, ingredient_id)
  end

  @doc "Unticks everything on a meal's shopping list (and the dishes that had it all in)."
  def clear_bought(%Meal{id: id} = meal) do
    Repo.delete_all(from c in ShoppingCheck, where: c.meal_id == ^id)
    sync_ingredients_in(meal, nil)
  end

  # Re-derives "all ingredients in" for the meal's dishes that use `ingredient_id` (or any
  # ingredient, for nil). Dishes with no ingredients are left to be ticked by hand.
  defp sync_ingredients_in(%Meal{id: id}, ingredient_id) do
    rows =
      Repo.all(
        from di in DishIngredient,
          join: d in assoc(di, :meal_dish),
          left_join: c in ShoppingCheck,
          on: c.meal_id == d.meal_id and c.ingredient_id == di.ingredient_id,
          where: d.meal_id == ^id,
          select: {d.id, di.ingredient_id, not is_nil(c.id)}
      )

    for {meal_dish_id, dish_rows} <- Enum.group_by(rows, &elem(&1, 0)),
        is_nil(ingredient_id) or Enum.any?(dish_rows, &(elem(&1, 1) == ingredient_id)) do
      all_in = Enum.all?(dish_rows, &elem(&1, 2))

      Repo.update_all(from(d in MealDish, where: d.id == ^meal_dish_id),
        set: [ingredients_in: all_in]
      )
    end

    :ok
  end

  @doc "A dish's ingredients as `[%DishIngredient{ingredient: ...}]`, A to Z. Takes a meal dish or a dish."
  def list_dish_ingredients(%MealDish{id: id}), do: ingredients_for({:meal_dish, id})
  def list_dish_ingredients(%Dish{id: id}), do: ingredients_for({:dish, id})

  defp ingredients_for(owner) do
    Repo.all(
      from di in owner_query(owner),
        join: i in assoc(di, :ingredient),
        order_by: fragment("lower(?)", i.name),
        preload: [ingredient: i]
    )
  end

  @doc """
  Adds an ingredient to a dish, creating it in the shared list if it's new (names match
  regardless of case). `amount` is a number or text like "50" or "1/2"; `unit` is one of
  `DishIngredient.units/0` (none means a count). Adding one the dish already has just
  updates the amount.

  Returns `{:error, :name}` or `{:error, :amount}` when either can't be used.
  """
  def add_ingredient(dish, name, amount \\ nil, unit \\ nil) do
    owner = owner(dish)

    with {:ok, amount} <- parse_amount(amount),
         {:ok, ingredient} <- find_or_create_ingredient(name) do
      # a unit means nothing without an amount
      attrs = [
        ingredient_id: ingredient.id,
        amount: amount,
        unit: if(amount, do: DishIngredient.parse_unit(unit))
      ]

      result =
        case Repo.one(from di in owner_query(owner), where: di.ingredient_id == ^ingredient.id) do
          nil ->
            Repo.insert(struct(DishIngredient, [{owner_key(owner), elem(owner, 1)} | attrs]))

          existing ->
            existing |> Ecto.Changeset.change(Map.new(attrs)) |> Repo.update()
        end

      with {:ok, di} <- result do
        sync_ingredients_to_library(dish)
        {:ok, di}
      end
    end
  end

  defp parse_amount(amount) do
    case DishIngredient.parse_amount(amount) do
      :error -> {:error, :amount}
      ok -> ok
    end
  end

  @doc "Takes an ingredient off a dish. The ingredient stays in the shared list."
  def remove_ingredient(dish, %DishIngredient{} = di) do
    result = Repo.delete(di)
    sync_ingredients_to_library(dish)
    result
  end

  defp find_or_create_ingredient(name) do
    changeset = Ingredient.changeset(%Ingredient{}, %{name: name})

    case Ecto.Changeset.fetch_change(changeset, :name) do
      {:ok, trimmed} when trimmed != "" ->
        key = String.downcase(trimmed)

        case Repo.one(from i in Ingredient, where: fragment("lower(?)", i.name) == ^key) do
          nil -> Repo.insert(changeset)
          existing -> {:ok, existing}
        end

      _ ->
        {:error, :name}
    end
  end

  defp owner(%MealDish{id: id}), do: {:meal_dish, id}
  defp owner(%Dish{id: id}), do: {:dish, id}

  defp owner_key({:meal_dish, _}), do: :meal_dish_id
  defp owner_key({:dish, _}), do: :dish_id

  defp owner_query({:meal_dish, id}),
    do: from(di in DishIngredient, where: di.meal_dish_id == ^id)

  defp owner_query({:dish, id}), do: from(di in DishIngredient, where: di.dish_id == ^id)

  defp copy_ingredients(from_owner, to_owner) do
    for di <- Repo.all(owner_query(from_owner)) do
      Repo.insert!(
        struct(DishIngredient, [
          {owner_key(to_owner), elem(to_owner, 1)},
          ingredient_id: di.ingredient_id,
          amount: di.amount,
          unit: di.unit
        ])
      )
    end

    :ok
  end

  # Same rule as the other details: ingredient edits on a meal dish flow back to its library
  # dish (unless it's a placeholder or the meal has been started). Editing a library dish
  # itself pushes its ingredients on to its unstarted meals (see below).
  defp sync_ingredients_to_library(%MealDish{} = dish) do
    dish = Repo.get!(MealDish, dish.id)

    if library_worthy?(dish) and not started?(dish.meal_id) do
      sync_to_library(dish)
      dish = Repo.get!(MealDish, dish.id)
      Repo.delete_all(owner_query({:dish, dish.dish_id}))
      copy_ingredients({:meal_dish, dish.id}, {:dish, dish.dish_id})
    end

    :ok
  end

  # The other way round: a library dish's ingredients also replace those of its copies in
  # meals that haven't been started (planning or prepping). Started meals are history.
  defp sync_ingredients_to_library(%Dish{} = dish), do: push_ingredients_to_meals(dish)

  @doc """
  Copies a library dish's ingredients onto its dishes in meals still being planned or prepped,
  replacing what they had. Meals being cooked or finished are left alone.
  """
  def push_ingredients_to_meals(%Dish{id: id}) do
    targets =
      Repo.all(
        from d in MealDish,
          join: m in assoc(d, :meal),
          where: d.dish_id == ^id and m.status in [:planning, :prepping],
          select: d.id
      )

    for meal_dish_id <- targets do
      Repo.delete_all(owner_query({:meal_dish, meal_dish_id}))
      copy_ingredients({:dish, id}, {:meal_dish, meal_dish_id})
    end

    :ok
  end
end
