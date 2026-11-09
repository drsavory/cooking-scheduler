defmodule CookingSchedulerWeb.SetupLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.Kitchen

  test "shows empty state", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/setup")
    assert html =~ "No ovens yet"
  end

  test "finished is disabled until something is added, then goes home", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/setup")
    refute has_element?(lv, "#finished")
    assert html =~ "Add at least one"

    lv |> element("#quick-add button", "Microwave") |> render_click()

    {:ok, home, _html} =
      lv |> element("#finished") |> render_click() |> follow_redirect(conn, ~p"/")

    assert has_element?(home, "#new-meal-form")
  end

  test "adding an oven creates an editable default", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/setup")
    lv |> element(~s|#add-oven button[phx-value-unit="celsius"]|) |> render_click()

    [oven] = Kitchen.list_appliances()
    assert %{kind: :oven, name: "Oven", temp_unit: :celsius, max_temp: 250.0} = oven
    assert has_element?(lv, "#appliance-card-#{oven.id}")
  end

  test "adds a gas mark oven in one tap", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/setup")
    lv |> element(~s|#add-oven button[phx-value-unit="gas_mark"]|) |> render_click()

    assert [%{temp_unit: :gas_mark, min_temp: 0.25, max_temp: 9.0}] = Kitchen.list_appliances()
  end

  test "editing an oven inline autosaves", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/setup")
    lv |> element(~s|#add-oven button[phx-value-unit="celsius"]|) |> render_click()
    [oven] = Kitchen.list_appliances()

    lv
    |> form("#appliance-#{oven.id}-form", appliance: %{name: "Aga", max_temp: "230"})
    |> render_change()

    assert %{name: "Aga", max_temp: 230.0} = Kitchen.get_appliance!(oven.id)
  end

  test "switching scale resets the range to that scale", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/setup")
    lv |> element(~s|#add-oven button[phx-value-unit="celsius"]|) |> render_click()
    [oven] = Kitchen.list_appliances()

    lv
    |> form("#appliance-#{oven.id}-form", appliance: %{temp_unit: "gas_mark"})
    |> render_change()

    assert %{temp_unit: :gas_mark, min_temp: 0.25, max_temp: 9.0} =
             Kitchen.get_appliance!(oven.id)
  end

  test "invalid values are flagged and not saved", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/setup")
    lv |> element(~s|#add-oven button[phx-value-unit="celsius"]|) |> render_click()
    [oven] = Kitchen.list_appliances()

    lv
    |> form("#appliance-#{oven.id}-form", appliance: %{temp_unit: "gas_mark"})
    |> render_change()

    html =
      lv |> form("#appliance-#{oven.id}-form", appliance: %{max_temp: "250"}) |> render_change()

    assert html =~ "gas marks go from ¼ to 10"
    assert Kitchen.get_appliance!(oven.id).max_temp == 9.0
  end

  test "counts individual rings by size", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/setup")

    for {size, n} <- [medium: 4, small: 2, large: 2], _ <- 1..n do
      lv |> element(~s|button[phx-value-size=#{size}][phx-value-delta="1"]|) |> render_click()
    end

    assert render(lv) =~ "8 rings in total"
    assert Kitchen.ring_counts() == %{small: 2, medium: 4, large: 2}

    # each ring is its own record with its own name
    names = Kitchen.list_appliances() |> Enum.filter(&(&1.kind == :ring)) |> Enum.map(& &1.name)
    assert length(Enum.uniq(names)) == 8
    assert "Medium ring 4" in names

    lv |> element(~s|button[phx-value-size=medium][phx-value-delta="-1"]|) |> render_click()
    assert Kitchen.ring_counts().medium == 3
    assert render(lv) =~ "7 rings in total"
  end

  test "can't remove below zero", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/setup")
    assert has_element?(lv, ~s|button[phx-value-size=small][phx-value-delta="-1"][disabled]|)
    render_click(lv, "ring", %{"size" => "small", "delta" => "-1"})
    assert Kitchen.ring_counts().small == 0
  end

  test "quick-adds another appliance, edits notes, then removes it", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/setup")

    lv |> element(~s|#quick-add button[phx-value-name="Slow cooker"]|) |> render_click()
    [cooker] = Enum.filter(Kitchen.list_appliances(), &(&1.kind == :other))
    assert cooker.name == "Slow cooker"

    lv |> form("#appliance-#{cooker.id}-form", appliance: %{notes: "6.5L"}) |> render_change()
    assert Kitchen.get_appliance!(cooker.id).notes == "6.5L"

    confirm_dialog(lv, "delete-appliance-#{cooker.id}")
    refute has_element?(lv, "#appliance-card-#{cooker.id}")
  end
end
