defmodule CookingSchedulerWeb.SessionControllerTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.Kitchen

  @password "open-sesame"

  setup do
    Application.put_env(:cooking_scheduler, :site_password, @password)
    on_exit(fn -> Application.delete_env(:cooking_scheduler, :site_password) end)
    {:ok, _} = Kitchen.add_oven(:gas_mark)
    :ok
  end

  defp log_in(conn), do: post(conn, ~p"/login", session: %{password: @password})

  test "every page is shut until the password is given", %{conn: conn} do
    assert conn |> get(~p"/") |> redirected_to() == ~p"/login"
    assert conn |> get(~p"/photos/1") |> redirected_to() == ~p"/login"
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/setup")
  end

  test "the login page asks for the password and rejects a wrong one", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ ~s|id="login-form"|

    conn = post(conn, ~p"/login", session: %{password: "nope"})
    assert html_response(conn, 401) =~ ~s|id="login-error"|
    assert conn |> get(~p"/") |> redirected_to() == ~p"/login"
  end

  test "the right password opens everything, and logging out shuts it again", %{conn: conn} do
    conn = log_in(conn)
    assert redirected_to(conn) == ~p"/"

    assert conn |> get(~p"/") |> html_response(200) =~ ~s|id="log-out"|
    assert conn |> get(~p"/photos/999999") |> response(404)
    assert {:ok, _lv, _html} = live(conn, ~p"/setup")

    conn = delete(conn, ~p"/logout")
    assert redirected_to(conn) == ~p"/login"
    assert conn |> get(~p"/") |> redirected_to() == ~p"/login"
  end

  test "with no password set there is no gate and no login page", %{conn: conn} do
    Application.delete_env(:cooking_scheduler, :site_password)

    assert conn |> get(~p"/login") |> redirected_to() == ~p"/"
    html = conn |> get(~p"/") |> html_response(200)
    refute html =~ ~s|id="log-out"|
  end
end
