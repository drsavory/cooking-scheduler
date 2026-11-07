defmodule CookingSchedulerWeb.DishFormLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.Meals

  test "creates a dish and returns home", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes/new")

    lv
    |> form("#dish-form",
      saved_dish: %{name: "Nut roast", temp: "6", cook_minutes: "1h 10m", rest_minutes: "0:15"}
    )
    |> render_submit()

    assert_redirect(lv, ~p"/")

    assert [%{name: "Nut roast", temp: 6.0, cook_minutes: 70, rest_minutes: 15}] =
             Meals.list_saved_dishes()
  end

  test "flags bad input and saves nothing", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes/new")

    html =
      lv
      |> form("#dish-form", saved_dish: %{name: "", cook_minutes: "soon"})
      |> render_change()

    assert html =~ "try 1:30"
    assert html =~ "can&#39;t be blank"
    assert Meals.list_saved_dishes() == []
  end

  test "hob dishes ask for a ring size instead of a temperature", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes/new")
    lv |> form("#dish-form", saved_dish: %{method: "ring"}) |> render_change()

    assert has_element?(lv, "#dish-form select[name='saved_dish[ring_size]']")
    refute has_element?(lv, "#dish-form input[name='saved_dish[temp]']")
  end

  test "edits an existing dish", %{conn: conn} do
    {:ok, d} = Meals.create_saved_dish(%{name: "Gravy", method: :appliance, cook_minutes: 10})
    {:ok, lv, _} = live(conn, ~p"/dishes/#{d.id}/edit")

    lv |> form("#dish-form", saved_dish: %{cook_minutes: "20"}) |> render_submit()
    assert_redirect(lv, ~p"/")
    assert Meals.get_saved_dish!(d.id).cook_minutes == 20
  end
end
