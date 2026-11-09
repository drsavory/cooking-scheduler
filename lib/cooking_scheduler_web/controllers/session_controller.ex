defmodule CookingSchedulerWeb.SessionController do
  @moduledoc "The site password page (ADR 0015)."
  use CookingSchedulerWeb, :controller

  alias CookingSchedulerWeb.Auth

  def new(conn, _params) do
    if Auth.enabled?(), do: render_form(conn, nil), else: redirect(conn, to: ~p"/")
  end

  def create(conn, params) do
    if Auth.correct?(get_in(params, ["session", "password"])) do
      conn |> Auth.log_in() |> redirect(to: ~p"/")
    else
      conn |> put_status(:unauthorized) |> render_form("That's not the password.")
    end
  end

  def delete(conn, _params), do: conn |> Auth.log_out() |> redirect(to: ~p"/login")

  defp render_form(conn, error) do
    render(conn, :new, form: Phoenix.Component.to_form(%{}, as: :session), error: error)
  end
end
