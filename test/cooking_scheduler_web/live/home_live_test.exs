defmodule CookingSchedulerWeb.HomeLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.Kitchen

  test "first visit goes to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/setup"}}} = live(conn, ~p"/")
  end

  test "shows the kitchen summary and links back to setup", %{conn: conn} do
    {:ok, _} = Kitchen.add_oven(:gas_mark)
    {:ok, _} = Kitchen.adjust_rings(:large, 1)

    {:ok, lv, html} = live(conn, ~p"/")
    assert html =~ "Your kitchen is ready"
    assert html =~ "Gas mark"
    assert html =~ "large"

    {:ok, _lv, setup} =
      lv |> element("#edit-kitchen") |> render_click() |> follow_redirect(conn, ~p"/setup")

    assert setup =~ "Set up your kitchen"
  end
end
