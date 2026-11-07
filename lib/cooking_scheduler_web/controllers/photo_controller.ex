defmodule CookingSchedulerWeb.PhotoController do
  @moduledoc "Serves a stored photo. The bucket is private, so every image goes through here."
  use CookingSchedulerWeb, :controller

  alias CookingScheduler.{Photos, Storage}

  def show(conn, %{"id" => id}) do
    with {int, ""} <- Integer.parse(id),
         %{} = photo <- CookingScheduler.Repo.get(Photos.Photo, int),
         {:ok, body} <- Storage.get(photo.key) do
      conn
      |> put_resp_content_type(photo.content_type, nil)
      |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, body)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
