defmodule CookingSchedulerWeb.PhotoControllerTest do
  use CookingSchedulerWeb.ConnCase

  alias CookingScheduler.{Meals, Photos}

  test "serves a stored photo with its content type", %{conn: conn} do
    {:ok, meal} = Meals.create_meal(%{name: "Christmas"})
    path = Path.join(System.tmp_dir!(), "ctl-#{System.unique_integer([:positive])}")
    File.write!(path, <<0xFF, 0xD8, 0xFF, 1, 2, 3>>)
    {:ok, photo} = Photos.add_photo(meal, path, "x.jpg")

    conn = conn |> put_req_header("accept", "image/avif,image/*") |> get(~p"/photos/#{photo.id}")

    assert response(conn, 200) == <<0xFF, 0xD8, 0xFF, 1, 2, 3>>
    assert [type] = get_resp_header(conn, "content-type")
    assert type =~ "image/jpeg"
  end

  test "404s for a missing photo", %{conn: conn} do
    assert conn |> get(~p"/photos/999999") |> response(404)
    assert conn |> get(~p"/photos/nope") |> response(404)
  end
end
