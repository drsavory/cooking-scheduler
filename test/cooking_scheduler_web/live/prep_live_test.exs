defmodule CookingSchedulerWeb.PrepLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.Meals

  setup do
    {:ok, meal} = Meals.create_meal(%{name: "Sunday lunch"})

    {:ok, with_prep} =
      Meals.create_meal_dish(meal, %{
        name: "Potatoes",
        method: :ring,
        ring_size: :large,
        prep_minutes: 20,
        cook_minutes: 30
      })

    {:ok, no_prep} =
      Meals.create_meal_dish(meal, %{
        name: "Gravy",
        method: :ring,
        ring_size: :small,
        cook_minutes: 10
      })

    {:ok, _} = Meals.add_ingredient(with_prep, "Potatoes", 1, :kg)
    %{meal: meal, with_prep: with_prep, no_prep: no_prep}
  end

  test "ticks made on the shopping list show up on an open prep screen", %{
    conn: conn,
    meal: meal,
    with_prep: with_prep
  } do
    {:ok, prep, _} = live(conn, ~p"/meals/#{meal.id}/prep")
    {:ok, shop, _} = live(Phoenix.ConnTest.build_conn(), ~p"/meals/#{meal.id}/shopping")
    [%{ingredient: potatoes}] = Meals.shopping_list(meal)

    refute has_element?(prep, "#tick-ingredients-#{with_prep.id}[aria-checked=true]")
    shop |> element("#tick-shopping-#{potatoes.id}") |> render_click()
    assert has_element?(prep, "#tick-ingredients-#{with_prep.id}[aria-checked=true]")
    assert has_element?(prep, "#shopping-summary", "1 of 1 bought")
  end

  test "planning meals offer to start prepping", %{conn: conn, meal: meal} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/prep")
    assert has_element?(lv, "#not-prepping")
    lv |> element("#start-prepping") |> render_click()
    refute has_element?(lv, "#not-prepping")
    assert Meals.get_meal!(meal.id).status == :prepping
  end

  test "only dishes with prep time get a prep step", %{
    conn: conn,
    meal: meal,
    with_prep: p,
    no_prep: g
  } do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/prep")
    assert has_element?(lv, "#tick-prepped-#{p.id}")
    refute has_element?(lv, "#tick-prepped-#{g.id}")
    assert has_element?(lv, "#tick-ingredients-#{g.id}")
  end

  test "ticking ingredients and prep is saved and shown in progress", %{
    conn: conn,
    meal: meal,
    with_prep: p
  } do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/prep")
    assert has_element?(lv, "#prep-progress", "0 of 3 done")

    lv |> element("#tick-ingredients-#{p.id}") |> render_click()
    lv |> element("#tick-prepped-#{p.id}") |> render_click()
    assert Meals.get_meal_dish!(p.id).ingredients_in
    assert Meals.get_meal_dish!(p.id).prepped
    assert has_element?(lv, "#prep-progress", "2 of 3 done")

    lv |> element("#tick-prepped-#{p.id}") |> render_click()
    refute Meals.get_meal_dish!(p.id).prepped
  end

  test "everything's in ticks every dish", %{conn: conn, meal: meal, with_prep: p, no_prep: g} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/prep")
    lv |> element("#all-ingredients-in") |> render_click()
    assert Meals.get_meal_dish!(p.id).ingredients_in
    assert Meals.get_meal_dish!(g.id).ingredients_in
  end

  test "plan screen leads to prep", %{conn: conn, meal: meal} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/plan")
    lv |> element("#prep-meal") |> render_click()
    assert_redirect(lv, ~p"/meals/#{meal.id}/prep")
    assert Meals.get_meal!(meal.id).status == :prepping
  end

  test "shopping list totals amounts across dishes, combining metric units", %{
    conn: conn,
    meal: meal,
    with_prep: p,
    no_prep: g
  } do
    {:ok, _} = Meals.add_ingredient(g, "potatoes", 500, :g)
    {:ok, _} = Meals.add_ingredient(g, "Stock", nil)
    {:ok, _} = Meals.add_ingredient(p, "Onion", 2)
    {:ok, _} = Meals.add_ingredient(g, "Onion", 1)

    [onion, potatoes, stock] = Meals.shopping_list(meal)
    assert onion.amounts == [{3.0, nil}]
    assert onion.dishes == ["Gravy", "Potatoes"]
    assert potatoes.amounts == [{1.5, :kg}]
    assert stock.amounts == []

    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/prep")
    assert has_element?(lv, "#shopping-summary", "0 of 3 bought")

    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/shopping")
    assert has_element?(lv, "#shopping-#{onion.ingredient.id}", "3 items")
    assert has_element?(lv, "#shopping-#{potatoes.ingredient.id}", "1.5 kg")
  end

  test "shopping items can be ticked off and unticked", %{conn: conn, meal: meal, with_prep: p} do
    {:ok, _} = Meals.add_ingredient(p, "Onion", 2)
    [onion, potatoes] = Meals.shopping_list(meal)

    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/shopping")
    assert has_element?(lv, "#to-buy #shopping-#{onion.ingredient.id}")

    lv |> element("#tick-shopping-#{onion.ingredient.id}") |> render_click()
    assert has_element?(lv, "#bought #shopping-#{onion.ingredient.id}")
    assert has_element?(lv, "#shopping-progress", "1 of 2 bought")
    assert [%{bought?: true}, %{bought?: false}] = Meals.shopping_list(meal)

    # ticks belong to the meal
    {:ok, other} = Meals.create_meal(%{name: "Other"})
    {:ok, od} = Meals.create_meal_dish(other, %{name: "Mash", method: :ring, ring_size: :small})
    {:ok, _} = Meals.add_ingredient(od, "Onion", 1)
    assert [%{bought?: false}] = Meals.shopping_list(other)

    lv |> element("#tick-shopping-#{onion.ingredient.id}") |> render_click()
    refute has_element?(lv, "#bought")

    lv |> element("#tick-shopping-#{potatoes.ingredient.id}") |> render_click()
    lv |> element("#clear-bought") |> render_click()
    assert Enum.all?(Meals.shopping_list(meal), &(not &1.bought?))
  end

  test "buying every ingredient of a dish ticks it in, and unticking reverses it", %{
    conn: conn,
    meal: meal,
    with_prep: p,
    no_prep: g
  } do
    {:ok, _} = Meals.add_ingredient(p, "Onion", 2)
    {:ok, _} = Meals.add_ingredient(g, "Stock", 1)
    [onion, potatoes, stock] = Meals.shopping_list(meal)

    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/shopping")
    lv |> element("#tick-shopping-#{onion.ingredient.id}") |> render_click()
    refute Meals.get_meal_dish!(p.id).ingredients_in

    lv |> element("#tick-shopping-#{potatoes.ingredient.id}") |> render_click()
    assert Meals.get_meal_dish!(p.id).ingredients_in
    refute Meals.get_meal_dish!(g.id).ingredients_in

    lv |> element("#tick-shopping-#{stock.ingredient.id}") |> render_click()
    assert Meals.get_meal_dish!(g.id).ingredients_in

    lv |> element("#tick-shopping-#{onion.ingredient.id}") |> render_click()
    refute Meals.get_meal_dish!(p.id).ingredients_in
    assert Meals.get_meal_dish!(g.id).ingredients_in

    lv |> element("#clear-bought") |> render_click()
    refute Meals.get_meal_dish!(g.id).ingredients_in
  end

  test "dishes with no ingredients are left alone", %{meal: meal, with_prep: p, no_prep: g} do
    {:ok, _} = Meals.add_ingredient(p, "Onion", 2)
    {:ok, _} = Meals.set_ingredients_in(g, true)
    [onion, _potatoes] = Meals.shopping_list(meal)

    :ok = Meals.set_bought(meal, onion.ingredient.id, true)
    :ok = Meals.clear_bought(meal)
    assert Meals.get_meal_dish!(g.id).ingredients_in
  end

  test "each dish shows which ingredients are in and which are missing", %{
    conn: conn,
    meal: meal,
    with_prep: p
  } do
    {:ok, _} = Meals.add_ingredient(p, "Onion", 2)
    [onion, potatoes] = Meals.shopping_list(meal)
    :ok = Meals.set_bought(meal, onion.ingredient.id, true)

    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/prep")
    assert has_element?(lv, ~s|#dish-#{p.id}-ingredient-#{onion.ingredient.id}[data-state="in"]|)

    assert has_element?(
             lv,
             ~s|#dish-#{p.id}-ingredient-#{potatoes.ingredient.id}[data-state="missing"]|
           )
  end
end
