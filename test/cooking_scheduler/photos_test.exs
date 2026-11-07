defmodule CookingScheduler.PhotosTest do
  use CookingScheduler.DataCase

  alias CookingScheduler.{Meals, Photos, Storage}

  @png <<0x89, "PNG\r\n", 0x1A, "\n", 0, 0, 0, 13>>

  defp tmp_file(contents) do
    path = Path.join(System.tmp_dir!(), "photo-#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  setup do
    {:ok, meal} = Meals.create_meal(%{name: "Christmas"})

    {:ok, dish} =
      Meals.create_meal_dish(meal, %{name: "Turkey", method: :ring, ring_size: :large})

    %{meal: meal, dish: dish}
  end

  test "stores a picture against a meal and a dish", %{meal: meal, dish: dish} do
    assert {:ok, photo} = Photos.add_photo(meal, tmp_file(@png), "table.png")
    assert photo.content_type == "image/png"
    assert {:ok, @png} = Storage.get(photo.key)
    assert {:ok, dish_photo} = Photos.add_photo(dish, tmp_file(@png), "turkey.png")

    assert [%{id: id}] = Photos.list_photos(meal)
    assert id == photo.id
    assert [%{id: did}] = Photos.list_photos(dish)
    assert did == dish_photo.id
    assert Photos.covers_for_meal_dishes([dish.id])[dish.id].id == dish_photo.id
  end

  test "judges a file by its contents, not its name", %{meal: meal} do
    assert {:error, :not_an_image} = Photos.add_photo(meal, tmp_file("<script>"), "x.png")
    assert Photos.list_photos(meal) == []
  end

  test "rejects files over the size limit", %{meal: meal} do
    big = @png <> :binary.copy(<<0>>, Photos.max_bytes())
    assert {:error, :too_large} = Photos.add_photo(meal, tmp_file(big), "big.png")
  end

  test "deleting a photo removes its file", %{meal: meal} do
    {:ok, photo} = Photos.add_photo(meal, tmp_file(@png), "a.png")
    assert {:ok, _} = Photos.delete_photo(photo)
    assert {:error, :enoent} = Storage.get(photo.key)
  end

  test "deleting a meal removes its photos and its dishes' photos", %{meal: meal, dish: dish} do
    {:ok, a} = Photos.add_photo(meal, tmp_file(@png), "a.png")
    {:ok, b} = Photos.add_photo(dish, tmp_file(@png), "b.png")

    assert {:ok, _} = Meals.delete_meal(meal)

    assert Repo.all(Photos.Photo) == []
    assert {:error, :enoent} = Storage.get(a.key)
    assert {:error, :enoent} = Storage.get(b.key)
  end

  test "deleting a dish removes its photos", %{meal: meal, dish: dish} do
    {:ok, keep} = Photos.add_photo(meal, tmp_file(@png), "keep.png")
    {:ok, gone} = Photos.add_photo(dish, tmp_file(@png), "gone.png")

    assert {:ok, _} = Meals.delete_meal_dish(dish)

    assert {:error, :enoent} = Storage.get(gone.key)
    assert {:ok, _} = Storage.get(keep.key)
  end

  test "a library dish gathers the photos of every meal it was cooked in", %{dish: dish} do
    library = Meals.get_dish!(Meals.get_meal_dish!(dish.id).dish_id)
    {:ok, other} = Meals.create_meal(%{name: "Easter", date: ~D[2027-04-04]})
    {:ok, other_dish} = Meals.add_dish_to_meal(other, library)
    {:ok, a} = Photos.add_photo(dish, tmp_file(@png), "a.png")
    {:ok, b} = Photos.add_photo(other_dish, tmp_file(@png), "b.png")

    assert [{%{id: first}, %{name: "Easter"}}, {%{id: second}, %{name: "Christmas"}}] =
             Photos.list_for(library)

    assert {first, second} == {b.id, a.id}
    assert [{%{id: only}, _}] = Photos.list_for(dish)
    assert only == a.id
  end
end
