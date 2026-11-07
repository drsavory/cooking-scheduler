defmodule CookingScheduler.Storage.Local do
  @moduledoc """
  Keeps files on disk (under `:root`, default `tmp/storage`), so uploads work in development
  and tests without a bucket. Not for production.
  """
  @behaviour CookingScheduler.Storage

  @impl true
  def put(key, body, _content_type) do
    path = path(key)

    with :ok <- File.mkdir_p(Path.dirname(path)), do: File.write(path, body)
  end

  @impl true
  def get(key), do: File.read(path(key))

  @impl true
  def delete(key) do
    case File.rm(path(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  # `Path.expand(key, "/")` stops a key from escaping the root with `..`.
  defp path(key), do: Path.join([root(), Path.expand(key, "/")])

  defp root do
    config = Application.get_env(:cooking_scheduler, __MODULE__, [])
    Path.expand(config[:root] || "tmp/storage", File.cwd!())
  end
end
