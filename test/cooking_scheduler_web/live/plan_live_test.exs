defmodule CookingSchedulerWeb.PlanLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.{Kitchen, Meals}

  setup do
    {:ok, left} = Kitchen.add_oven(:gas_mark)
    {:ok, _right} = Kitchen.add_oven(:gas_mark)
    for size <- [:medium, :medium, :large], do: {:ok, _} = Kitchen.adjust_rings(size, 1)
    {:ok, grill} = Kitchen.add_other("Grill")
    {:ok, _} = Kitchen.add_other("Slow cooker")
    {:ok, meal} = Meals.create_meal(%{name: "Christmas 2026"})
    %{left: left, grill: grill, meal: meal, path: ~p"/meals/#{meal.id}/plan"}
  end

  defp dishes(meal), do: Meals.list_meal_dishes(meal)

  # Adds a dish the way the screen does: open "Add a dish", switch to the New dish tab, and
  # submit the embedded form. Returns the parent's HTML once the modal has closed.
  defp add_new_dish(lv, attrs) do
    lv |> element("#add-dish") |> render_click()
    lv |> element("#add-tab-new") |> render_click()
    child = find_live_child(lv, "new-dish-form")
    # Method first: the ring size box only appears once "Hob" is chosen.
    child |> form("#dish-form", dish: Map.take(attrs, [:method])) |> render_change()
    child |> form("#dish-form", dish: attrs) |> render_submit()
    render(lv)
  end

  test "starts empty with an offer to load last year's menu", %{
    conn: conn,
    meal: meal,
    path: path
  } do
    {:ok, lv, html} = live(conn, path)
    assert html =~ "No dishes in this meal yet"

    lv |> element("#start-from-last-year") |> render_click()

    names = dishes(meal) |> Enum.map(& &1.name)
    assert "Turkey (6.1 kg)" in names
    assert "Gravy" in names
    refute has_element?(lv, "#start-from-last-year")

    # appliance dishes find the user's matching appliance
    sprouts = Enum.find(dishes(meal), &(&1.name =~ "Umami sprouts (after"))
    assert sprouts.appliance_id
  end

  test "last year's menu schedules cleanly into the default kitchen", %{conn: conn, path: path} do
    {:ok, lv, _} = live(conn, path)
    lv |> element("#start-from-last-year") |> render_click()

    # turkey: 13:30 serve - 2h rest - 4h30 cook = 07:00 in the oven, prep from 06:00
    html = render(lv)
    assert html =~ "07:00"
    assert html =~ "06:00"
  end

  test "changing the serving time re-times every dish", %{conn: conn, meal: meal, path: path} do
    {:ok, lv, _} = live(conn, path)
    lv |> element("#start-from-last-year") |> render_click()

    html = lv |> form("#meal-form", meal: %{serve_at: "14:30"}) |> render_change()
    assert html =~ "08:00"
    assert Meals.get_meal!(meal.id).serve_at == ~T[14:30:00]
  end

  test "adds a dish and edits it inline, with times in friendly formats", %{
    conn: conn,
    meal: meal,
    path: path
  } do
    {:ok, lv, _} = live(conn, path)
    add_new_dish(lv, %{name: "Roast", method: :oven, temp: "7", cook_minutes: "1h"})
    [dish] = dishes(meal)
    refute has_element?(lv, "#add-dish-modal")

    lv
    |> form("#dish-#{dish.id}-form",
      meal_dish: %{name: "Nut roast", temp: "6", cook_minutes: "1h 10m", rest_minutes: "0:15"}
    )
    |> render_change()

    dish = Meals.get_meal_dish!(dish.id)
    assert %{name: "Nut roast", temp: 6.0, cook_minutes: 70, rest_minutes: 15} = dish
  end

  test "bad durations are flagged and not saved", %{conn: conn, meal: meal, path: path} do
    {:ok, lv, _} = live(conn, path)
    add_new_dish(lv, %{name: "Roast", method: :oven, temp: "7", cook_minutes: "1h"})
    [dish] = dishes(meal)

    html =
      lv |> form("#dish-#{dish.id}-form", meal_dish: %{cook_minutes: "soon"}) |> render_change()

    assert html =~ "try 1:30"
    assert Meals.get_meal_dish!(dish.id).cook_minutes == 60
  end

  test "hob dishes get individual rings; running out is flagged", %{conn: conn, path: path} do
    {:ok, lv, _} = live(conn, path)

    for n <- 1..4,
        do:
          add_new_dish(lv, %{
            name: "Pan #{n}",
            method: :ring,
            ring_size: :medium,
            cook_minutes: "20m"
          })

    html = render(lv)
    assert html =~ "Medium ring"
    assert html =~ "Large ring"
    assert html =~ "No free medium (or larger) ring"
  end

  test "removing a dish", %{conn: conn, meal: meal, path: path} do
    {:ok, lv, _} = live(conn, path)
    add_new_dish(lv, %{name: "Sprouts", method: :appliance, cook_minutes: "1h"})
    [dish] = dishes(meal)
    confirm_dialog(lv, "delete-dish-#{dish.id}")
    assert dishes(meal) == []
  end

  test "a saved dish that can't be copied is explained, not crashed on", %{conn: conn, path: path} do
    # Saved before gas marks were capped, so it no longer passes a meal dish's checks.
    CookingScheduler.Repo.insert!(%CookingScheduler.Meals.Dish{
      name: "Inferno",
      method: :oven,
      temp: 12.0,
      temp_unit: :gas_mark
    })

    {:ok, lv, _} = live(conn, path)
    lv |> element("#add-dish") |> render_click()
    lv |> element("#saved-picker button", "Inferno") |> render_click()

    assert has_element?(lv, "#flash-error", "Inferno can't be added")
    assert has_element?(lv, "#saved-picker button", "Inferno")
  end

  test "picking a dish from the library adds a copy and closes the modal", %{
    conn: conn,
    meal: meal,
    path: path
  } do
    {:ok, gravy} =
      Meals.create_dish(%{name: "Gravy", method: :ring, ring_size: :small, cook_minutes: "15m"})

    {:ok, _} =
      Meals.create_dish(%{
        name: "Bread sauce",
        method: :ring,
        ring_size: :small,
        cook_minutes: "20m"
      })

    {:ok, lv, _} = live(conn, path)
    lv |> element("#add-dish") |> render_click()
    assert has_element?(lv, "#add-dish-modal")
    assert has_element?(lv, "#saved-picker button", "Bread sauce")

    lv |> element("#saved-filter") |> render_change(%{q: "gra"})
    refute has_element?(lv, "#saved-picker button", "Bread sauce")

    lv |> element("#saved-picker button", "Gravy") |> render_click()

    refute has_element?(lv, "#add-dish-modal")
    assert [%{name: "Gravy", dish_id: dish_id}] = dishes(meal)
    assert dish_id == gravy.id

    # Already in the meal, so no longer offered.
    lv |> element("#add-dish") |> render_click()
    refute has_element?(lv, "#saved-picker button", "Gravy")
  end

  test "a new dish made in the modal lands in the library and the meal", %{
    conn: conn,
    meal: meal,
    path: path
  } do
    {:ok, lv, _} = live(conn, path)
    add_new_dish(lv, %{name: "Nut roast", method: :oven, temp: "6", cook_minutes: "1h 10m"})

    assert [%{name: "Nut roast", cook_minutes: 70}] = dishes(meal)
    assert Enum.any?(Meals.list_dishes(), &(&1.name == "Nut roast"))
    assert has_element?(lv, "#flash-info", "Nut roast added")
  end

  test "cancelling the new dish form closes the modal", %{conn: conn, path: path} do
    {:ok, lv, _} = live(conn, path)
    lv |> element("#add-dish") |> render_click()
    lv |> element("#add-tab-new") |> render_click()
    lv |> find_live_child("new-dish-form") |> element("#cancel-dish") |> render_click()
    refute has_element?(lv, "#add-dish-modal")
  end

  test "changes made on another screen show up here", %{conn: conn, meal: meal, path: path} do
    {:ok, lv, _} = live(conn, path)
    {:ok, other, _} = live(Phoenix.ConnTest.build_conn(), path)

    add_new_dish(other, %{name: "Peas", method: :ring, ring_size: :small, cook_minutes: "5m"})
    [dish] = dishes(meal)

    assert has_element?(lv, "#dish-card-#{dish.id}")
  end

  test "can copy the meal into a new, independent one", %{conn: conn, meal: meal, path: path} do
    {:ok, lv, _} = live(conn, path)
    lv |> element("#start-from-last-year") |> render_click()

    {:error, {:live_redirect, %{to: to}}} = lv |> element("#copy-meal") |> render_click()
    copy = Meals.list_meals() |> Enum.find(&(&1.id != meal.id))
    assert to == "/meals/#{copy.id}/plan"
    assert length(dishes(copy)) == length(dishes(meal))
    assert Enum.all?(dishes(copy), &(&1.meal_id == copy.id))
  end

  test "links to cooking this meal", %{conn: conn, meal: meal, path: path} do
    {:ok, lv, _} = live(conn, path)
    assert has_element?(lv, ~s|#cook-meal[href="/meals/#{meal.id}/cook"]|)
  end

  test "shows how busy each appliance is", %{conn: conn, path: path} do
    {:ok, lv, _} = live(conn, path)
    refute has_element?(lv, "#kitchen-load")

    lv |> element("#start-from-last-year") |> render_click()
    assert has_element?(lv, "#kitchen-load")
    assert has_element?(lv, ~s|#kitchen-load [id^="load-"]|)
  end
end
