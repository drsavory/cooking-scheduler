defmodule CookingSchedulerWeb.DishesLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.{Kitchen, Meal}

  setup do
    {:ok, left} = Kitchen.add_oven(:gas_mark)
    {:ok, _right} = Kitchen.add_oven(:gas_mark)
    for size <- [:medium, :medium, :large], do: {:ok, _} = Kitchen.adjust_rings(size, 1)
    {:ok, grill} = Kitchen.add_other("Grill")
    {:ok, _} = Kitchen.add_other("Slow cooker")
    %{left: left, grill: grill}
  end

  test "starts empty with an offer to load last year's menu", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/dishes")
    assert html =~ "No dishes yet"

    lv |> element("#start-from-last-year") |> render_click()

    names = Meal.list_dishes() |> Enum.map(& &1.name)
    assert "Turkey (6.1 kg)" in names
    assert "Gravy" in names
    refute has_element?(lv, "#start-from-last-year")

    # appliance dishes find the user's matching appliance
    sprouts = Enum.find(Meal.list_dishes(), &(&1.name =~ "Umami sprouts (after"))
    assert sprouts.appliance_id
  end

  test "last year's menu schedules cleanly into the default kitchen", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes")
    lv |> element("#start-from-last-year") |> render_click()

    # turkey: 13:30 serve - 2h rest - 4h30 cook = 07:00 in the oven, prep from 06:00
    html = render(lv)
    assert html =~ "07:00"
    assert html =~ "06:00"
  end

  test "changing the serving time re-times every dish", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes")
    lv |> element("#start-from-last-year") |> render_click()

    html = lv |> form("#plan-form", plan: %{serve_at: "14:30"}) |> render_change()
    assert html =~ "08:00"
    assert Meal.get_plan().serve_at == ~T[14:30:00]
  end

  test "adds a dish and edits it inline, with times in friendly formats", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes")
    lv |> element(~s|#add-dish button[phx-value-method="oven"]|) |> render_click()
    [dish] = Meal.list_dishes()

    lv
    |> form("#dish-#{dish.id}-form",
      dish: %{name: "Nut roast", temp: "6", cook_minutes: "1h 10m", rest_minutes: "0:15"}
    )
    |> render_change()

    dish = Meal.get_dish!(dish.id)
    assert %{name: "Nut roast", temp: 6.0, cook_minutes: 70, rest_minutes: 15} = dish
  end

  test "bad durations are flagged and not saved", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes")
    lv |> element(~s|#add-dish button[phx-value-method="oven"]|) |> render_click()
    [dish] = Meal.list_dishes()

    html = lv |> form("#dish-#{dish.id}-form", dish: %{cook_minutes: "soon"}) |> render_change()
    assert html =~ "try 1:30"
    assert Meal.get_dish!(dish.id).cook_minutes == 60
  end

  test "hob dishes get individual rings; running out is flagged", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes")

    for _ <- 1..4,
        do: lv |> element(~s|#add-dish button[phx-value-method="ring"]|) |> render_click()

    html = render(lv)
    assert html =~ "Medium ring"
    assert html =~ "Large ring"
    assert html =~ "No free medium (or larger) ring"
  end

  test "removing a dish", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes")
    lv |> element(~s|#add-dish button[phx-value-method="appliance"]|) |> render_click()
    [dish] = Meal.list_dishes()
    lv |> element("#dish-card-#{dish.id} button[aria-label^=Remove]") |> render_click()
    assert Meal.list_dishes() == []
  end

  test "home links to dishes", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/")

    {:ok, _lv, html} =
      lv |> element("#plan-dishes") |> render_click() |> follow_redirect(conn, ~p"/dishes")

    assert html =~ "Plan your dishes"
  end
end
