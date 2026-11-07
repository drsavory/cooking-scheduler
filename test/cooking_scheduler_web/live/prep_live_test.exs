defmodule CookingSchedulerWeb.PrepLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.Meals

  setup do
    {:ok, meal} = Meals.create_meal(%{name: "Sunday lunch"})

    {:ok, with_prep} =
      Meals.create_dish(meal, %{
        name: "Potatoes",
        method: :ring,
        ring_size: :large,
        prep_minutes: 20,
        cook_minutes: 30
      })

    {:ok, no_prep} =
      Meals.create_dish(meal, %{name: "Gravy", method: :ring, ring_size: :small, cook_minutes: 10})

    {:ok, _} = Meals.add_ingredient(with_prep, "Potatoes", 1, :kg)
    %{meal: meal, with_prep: with_prep, no_prep: no_prep}
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
    assert Meals.get_dish!(p.id).ingredients_in
    assert Meals.get_dish!(p.id).prepped
    assert has_element?(lv, "#prep-progress", "2 of 3 done")

    lv |> element("#tick-prepped-#{p.id}") |> render_click()
    refute Meals.get_dish!(p.id).prepped
  end

  test "everything's in ticks every dish", %{conn: conn, meal: meal, with_prep: p, no_prep: g} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/prep")
    lv |> element("#all-ingredients-in") |> render_click()
    assert Meals.get_dish!(p.id).ingredients_in
    assert Meals.get_dish!(g.id).ingredients_in
  end

  test "plan screen leads to prep", %{conn: conn, meal: meal} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/plan")
    lv |> element("#prep-meal") |> render_click()
    assert_redirect(lv, ~p"/meals/#{meal.id}/prep")
    assert Meals.get_meal!(meal.id).status == :prepping
  end
end
