defmodule CookingSchedulerWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CookingSchedulerWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint CookingSchedulerWeb.Endpoint

      use CookingSchedulerWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import CookingSchedulerWeb.ConnCase
    end
  end

  @doc """
  Confirms a `<.confirm_button id={id}>` dialog: presses the dialog's Confirm button by
  sending the event it pushes. (LiveViewTest can't see inside the dialog, which is
  teleported to `<body>`.) Raises if the dialog doesn't exist.
  """
  def confirm_dialog(lv, id) do
    html = Phoenix.LiveViewTest.render(lv)

    [_, attrs] =
      Regex.run(
        ~r/<button[^>]*id="#{Regex.escape(id)}-dialog-confirm"[^>]*phx-click="([^"]*)"/,
        html
      ) ||
        raise "no confirm dialog #{inspect(id)} on the page"

    commands = attrs |> unescape() |> JSON.decode!()

    Enum.reduce(commands, :ok, fn
      ["push", %{"event" => event} = opts], _ ->
        Phoenix.LiveViewTest.render_hook(lv, event, Map.get(opts, "value", %{}))

      _other, acc ->
        acc
    end)
  end

  defp unescape(text) do
    text
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end

  setup tags do
    CookingScheduler.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
