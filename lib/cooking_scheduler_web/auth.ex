defmodule CookingSchedulerWeb.Auth do
  @moduledoc """
  One shared password for the whole site (ADR 0015).

  The password comes from `config :cooking_scheduler, :site_password` (`SITE_PASSWORD` in
  production). When it is nil nothing is protected, which is how development and tests run.
  Once given, the password is remembered in the session.
  """
  use CookingSchedulerWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @session_key "site_password_ok"

  @doc "Whether a password is set, and so required."
  def enabled?, do: password() != nil

  defp password, do: Application.get_env(:cooking_scheduler, :site_password)

  @doc "Checks a typed password, in constant time."
  def correct?(given) when is_binary(given) do
    enabled?() and Plug.Crypto.secure_compare(given, password())
  end

  def correct?(_given), do: false

  @doc "Marks the session as let in (with a fresh session id)."
  def log_in(conn), do: conn |> configure_session(renew: true) |> put_session(@session_key, true)

  @doc "Forgets the session entirely."
  def log_out(conn), do: configure_session(conn, drop: true)

  @doc "Plug: sends anyone not yet let in to the login page."
  def require_password(conn, _opts) do
    if let_in?(get_session(conn)) do
      conn
    else
      conn |> redirect(to: ~p"/login") |> halt()
    end
  end

  @doc "`on_mount` hook with the same rule for LiveViews."
  def on_mount(:require_password, _params, session, socket) do
    if let_in?(session) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  defp let_in?(session), do: not enabled?() or session[@session_key] == true
end
