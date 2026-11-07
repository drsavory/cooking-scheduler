defmodule CookingSchedulerWeb.SearchHook do
  @moduledoc """
  `on_mount` hook that answers the spotlight search (see `Layouts.app`) on every LiveView,
  so the dialog works from any page without each page loading search data.
  """
  import Phoenix.LiveView

  alias CookingScheduler.Search

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :spotlight_search, :handle_event, &handle_event/3)}
  end

  defp handle_event("spotlight_search", %{"q" => q}, socket) do
    {:halt, Search.search(q), socket}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
