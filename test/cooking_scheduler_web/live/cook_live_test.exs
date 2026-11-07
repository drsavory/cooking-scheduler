defmodule CookingSchedulerWeb.CookLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.{Kitchen, Meals}

  defp meal, do: hd(Meals.list_meals())
  defp dishes, do: Meals.list_dishes(meal())
  defp cook_path, do: "/meals/#{meal().id}/cook"

  defp set_clock(hour, minute),
    do: Application.put_env(:cooking_scheduler, :clock_value, hour * 60 + minute)

  setup do
    Application.put_env(:cooking_scheduler, :clock, fn ->
      Application.get_env(:cooking_scheduler, :clock_value)
    end)

    set_clock(5, 0)

    on_exit(fn ->
      Application.delete_env(:cooking_scheduler, :clock)
      Application.delete_env(:cooking_scheduler, :clock_value)
    end)

    {:ok, _} = Kitchen.add_oven(:gas_mark)
    {:ok, _} = Kitchen.add_oven(:gas_mark)
    for size <- [:medium, :medium, :medium, :large], do: {:ok, _} = Kitchen.adjust_rings(size, 1)
    {:ok, _} = Kitchen.add_other("Grill")

    {:ok, _} = Meals.load_starter_dishes(elem(Meals.create_meal(), 1), Kitchen.list_appliances())

    turkey = Enum.find(dishes(), &(&1.name =~ "Turkey"))
    # the starter menu has the turkey already prepped; un-prep it so there's a prep task to do
    {:ok, turkey} = Meals.set_prepped(turkey, false)
    %{turkey: turkey}
  end

  test "dishes already prepped have no prep task waiting", %{conn: conn} do
    potatoes = Enum.find(dishes(), &(&1.name == "Roast potatoes"))
    {:ok, lv, _} = live(conn, cook_path())
    refute has_element?(lv, "#task-#{potatoes.id}-prep")
  end

  test "shows the clock, dinner time and what's coming up", %{conn: conn, turkey: turkey} do
    {:ok, lv, html} = live(conn, cook_path())

    assert has_element?(lv, "#clock", "05:00")
    assert has_element?(lv, "#dinner-time", "13:30")
    assert has_element?(lv, "#status", "On track")
    # first job of the day: prep the turkey at 06:00, in the oven at 07:00
    assert has_element?(lv, "#task-#{turkey.id}-prep", "Prep Turkey")
    assert html =~ ~r/Put Turkey \(6\.1 kg\) in Oven/

    assert html =~ "Gas mark 7"
  end

  test "the clock moves on", %{conn: conn, turkey: turkey} do
    {:ok, lv, _} = live(conn, cook_path())
    set_clock(6, 20)
    send(lv.pid, :tick)
    assert has_element?(lv, "#clock", "06:20")
    # prep was due at 06:00 and isn't done
    assert has_element?(lv, "#task-#{turkey.id}-prep", "late")
  end

  test "marking things done moves them along and records the real time", %{
    conn: conn,
    turkey: turkey
  } do
    set_clock(7, 5)
    {:ok, lv, _} = live(conn, cook_path())

    lv |> element("#task-#{turkey.id}-prep button") |> render_click()
    assert Meals.get_dish!(turkey.id).prepped

    lv |> element("#task-#{turkey.id}-start button") |> render_click()
    assert Meals.get_dish!(turkey.id).cook_started_at == 7 * 60 + 5

    # now in progress, with an out time of actual start + 4h30
    assert has_element?(lv, "#cooking-#{turkey.id}", "Out at")
    assert has_element?(lv, "#cooking-#{turkey.id}", "11:35")
    refute has_element?(lv, "#task-#{turkey.id}-start")
  end

  test "starting late pushes dinner back and one tap moves it", %{conn: conn, turkey: turkey} do
    set_clock(7, 30)
    {:ok, lv, _} = live(conn, cook_path())
    # the turkey should've gone in at 07:00 and hasn't: dinner is projected 30 min late
    assert has_element?(lv, "#status", "Running 30m behind")
    assert has_element?(lv, "#push-dinner", "14:00")

    lv |> element("#push-dinner") |> render_click()
    assert has_element?(lv, "#dinner-time", "14:00")
    assert meal().serve_at == ~T[14:00:00]
    assert has_element?(lv, "#status", "On track")
    # ...and the turkey's start slid with it
    assert has_element?(lv, "#task-#{turkey.id}-start", "07:30")
  end

  test "taking longer: extra time extends the out time and the projected dinner", %{
    conn: conn,
    turkey: turkey
  } do
    set_clock(7, 0)
    {:ok, lv, _} = live(conn, cook_path())
    lv |> element("#task-#{turkey.id}-start button") |> render_click()
    assert has_element?(lv, "#status", "On track")

    lv |> element("#cooking-#{turkey.id} button", "+15m") |> render_click()
    assert Meals.get_dish!(turkey.id).extra_minutes == 15
    assert has_element?(lv, "#cooking-#{turkey.id}", "11:45")
    assert has_element?(lv, "#status", "Running 15m behind")
    assert has_element?(lv, "#push-dinner", "13:45")
  end

  test "out of the oven goes to resting", %{conn: conn, turkey: turkey} do
    set_clock(7, 0)
    {:ok, lv, _} = live(conn, cook_path())
    lv |> element("#task-#{turkey.id}-start button") |> render_click()

    set_clock(11, 30)
    send(lv.pid, :tick)
    lv |> element("#task-#{turkey.id}-out button") |> render_click()

    assert has_element?(lv, "#resting", "Turkey (6.1 kg)")
    assert has_element?(lv, "#resting", "13:30")
    refute has_element?(lv, "#cooking-#{turkey.id}")
  end

  test "undo puts a step back", %{conn: conn, turkey: turkey} do
    set_clock(7, 0)
    {:ok, lv, _} = live(conn, cook_path())
    lv |> element("#task-#{turkey.id}-start button") |> render_click()
    assert has_element?(lv, "#done-#{turkey.id}-start")

    lv |> element("#done-#{turkey.id}-start button", "undo") |> render_click()
    assert Meals.get_dish!(turkey.id).cook_started_at == nil
    assert has_element?(lv, "#task-#{turkey.id}-start")
  end

  test "dinner time can be nudged either way", %{conn: conn} do
    {:ok, lv, _} = live(conn, cook_path())
    lv |> element(~s|button[aria-label="Dinner 5 minutes later"]|) |> render_click()
    assert has_element?(lv, "#dinner-time", "13:35")
    lv |> element(~s|button[aria-label="Dinner 5 minutes earlier"]|) |> render_click()
    lv |> element(~s|button[aria-label="Dinner 5 minutes earlier"]|) |> render_click()
    assert has_element?(lv, "#dinner-time", "13:25")
  end

  test "reset clears progress but keeps the plan", %{conn: conn, turkey: turkey} do
    set_clock(7, 0)
    {:ok, lv, _} = live(conn, cook_path())
    lv |> element("#task-#{turkey.id}-start button") |> render_click()
    lv |> element("#cooking-#{turkey.id} button", "+10m") |> render_click()
    lv |> element("button", "Reset progress") |> render_click()

    assert %{cook_started_at: nil, extra_minutes: 0, name: "Turkey (6.1 kg)"} =
             Meals.get_dish!(turkey.id)
  end

  test "everything done shows the finish message", %{conn: conn} do
    set_clock(7, 0)
    {:ok, lv, _} = live(conn, cook_path())

    for d <- dishes() do
      Meals.set_prepped(d, true)
      Meals.start_cooking(d, 8 * 60)
      Meals.finish_cooking(Meals.get_dish!(d.id), 9 * 60)
    end

    {:ok, lv2, _} = live(Phoenix.ConnTest.build_conn(), cook_path())
    assert has_element?(lv2, "#all-done")
    refute has_element?(lv, "#all-done")
  end

  test "an empty meal points you to the dishes screen", %{conn: conn} do
    for d <- dishes(), do: Meals.delete_dish(d)
    {:ok, _lv, html} = live(conn, cook_path())
    assert html =~ "Nothing to cook yet"
  end

  test "finishing cooking ends the meal and returns home", %{conn: conn, turkey: turkey} do
    {:ok, _} = Meals.start_cooking(turkey, 420)
    {:ok, lv, _} = live(conn, cook_path())

    confirm_dialog(lv, "finish-cooking")
    assert_redirect(lv, ~p"/")
    assert [%{status: :cooked}] = Meals.list_meal_summaries()
  end
end
