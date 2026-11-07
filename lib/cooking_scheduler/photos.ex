defmodule CookingScheduler.Photos do
  @moduledoc """
  Photos of meals and of the dishes in them. Files are checked by their contents (not the
  name the browser gives), stored through `CookingScheduler.Storage`, and tracked in the
  `photos` table.
  """
  import Ecto.Query

  alias CookingScheduler.{Repo, Storage}
  alias CookingScheduler.Meals.{Dish, Meal, MealDish}
  alias CookingScheduler.Photos.Photo

  @max_bytes 10_000_000
  def max_bytes, do: @max_bytes

  @doc "File extensions the upload accepts."
  def accepted_extensions, do: ~w(.jpg .jpeg .png .webp .gif)

  def get_photo!(id), do: Repo.get!(Photo, id)

  @doc "A meal's own photos, oldest first."
  def list_photos(%Meal{id: id}), do: list_by(dynamic([p], p.meal_id == ^id))
  def list_photos(%MealDish{id: id}), do: list_by(dynamic([p], p.meal_dish_id == ^id))

  defp list_by(where), do: Repo.all(from p in Photo, where: ^where, order_by: p.id)

  @doc """
  Photos of a dish as `{photo, meal}` pairs, newest meal first. For a library `Dish` that is
  every photo of every meal dish copied from it, so a dish's pictures build up across meals;
  for a `MealDish` it is just that dish's own.
  """
  def list_for(%Dish{id: id}), do: pairs(dynamic([_p, md], md.dish_id == ^id))
  def list_for(%MealDish{id: id}), do: pairs(dynamic([p], p.meal_dish_id == ^id))

  defp pairs(where) do
    Repo.all(
      from p in Photo,
        join: md in assoc(p, :meal_dish),
        join: m in assoc(md, :meal),
        where: ^where,
        order_by: [desc: m.date, desc: m.id, asc: p.id],
        select: {p, m}
    )
  end

  @doc "The first photo of each of these meal dishes, as `%{meal_dish_id => photo}`."
  def covers_for_meal_dishes(ids) do
    Repo.all(
      from p in Photo,
        where: p.meal_dish_id in ^ids,
        distinct: p.meal_dish_id,
        order_by: [p.meal_dish_id, p.id]
    )
    |> Map.new(&{&1.meal_dish_id, &1})
  end

  @doc """
  Stores the file at `path` and records it against a meal or meal dish. Returns
  `{:error, :not_an_image}` when the contents aren't a JPEG, PNG, WebP or GIF, and
  `{:error, :too_large}` past #{div(@max_bytes, 1_000_000)} MB.
  """
  def add_photo(%owner_type{id: owner_id} = _owner, path, filename)
      when owner_type in [Meal, MealDish] do
    with {:ok, body} <- File.read(path),
         :ok <- check_size(body),
         {:ok, content_type} <- sniff(body) do
      key = "photos/#{Ecto.UUID.generate()}#{extension(content_type)}"

      with :ok <- Storage.put(key, body, content_type) do
        photo =
          %Photo{
            key: key,
            content_type: content_type,
            byte_size: byte_size(body),
            filename: filename && String.slice(filename, 0, 255)
          }
          |> Map.put(owner_field(owner_type), owner_id)

        case Repo.insert(photo) do
          {:ok, photo} ->
            {:ok, photo}

          error ->
            Storage.delete(key)
            error
        end
      end
    end
  end

  defp owner_field(Meal), do: :meal_id
  defp owner_field(MealDish), do: :meal_dish_id

  def delete_photo(%Photo{} = photo) do
    with {:ok, photo} <- Repo.delete(photo) do
      Storage.delete(photo.key)
      {:ok, photo}
    end
  end

  @doc "Keys of every photo on a meal and its dishes; collect before deleting, then `purge/1`."
  def keys_for_meal(%Meal{id: id}) do
    Repo.all(
      from p in Photo,
        left_join: d in assoc(p, :meal_dish),
        where: p.meal_id == ^id or d.meal_id == ^id,
        select: p.key
    )
  end

  def keys_for_meal_dish(%MealDish{id: id}),
    do: Repo.all(from p in Photo, where: p.meal_dish_id == ^id, select: p.key)

  @doc "Removes stored files whose rows are gone (the database cascades the rows)."
  def purge(keys), do: Enum.each(keys, &Storage.delete/1)

  defp check_size(body) when byte_size(body) > @max_bytes, do: {:error, :too_large}
  defp check_size(_), do: :ok

  defp sniff(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, "image/jpeg"}
  defp sniff(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: {:ok, "image/png"}
  defp sniff(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: {:ok, "image/webp"}
  defp sniff(<<"GIF8", _::binary>>), do: {:ok, "image/gif"}
  defp sniff(_), do: {:error, :not_an_image}

  defp extension("image/jpeg"), do: ".jpg"
  defp extension("image/png"), do: ".png"
  defp extension("image/webp"), do: ".webp"
  defp extension("image/gif"), do: ".gif"
end
